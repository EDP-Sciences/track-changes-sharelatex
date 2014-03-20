MongoManager = require "./MongoManager"
RedisManager = require "./RedisManager"
UpdateCompressor = require "./UpdateCompressor"
LockManager = require "./LockManager"
WebApiManager = require "./WebApiManager"
logger = require "logger-sharelatex"
async = require "async"

module.exports = UpdatesManager =
	compressAndSaveRawUpdates: (project_id, doc_id, rawUpdates, callback = (error) ->) ->
		length = rawUpdates.length
		if length == 0
			return callback()

		MongoManager.popLastCompressedUpdate doc_id, (error, lastCompressedUpdate) ->
			return callback(error) if error?

			# Ensure that raw updates start where lastCompressedUpdate left off
			if lastCompressedUpdate?
				rawUpdates = rawUpdates.slice(0)
				while rawUpdates[0]? and rawUpdates[0].v <= lastCompressedUpdate.v
					rawUpdates.shift()

				if rawUpdates[0]? and rawUpdates[0].v != lastCompressedUpdate.v + 1
					error = new Error("Tried to apply raw op at version #{rawUpdates[0].v} to last compressed update with version #{lastCompressedUpdate.v}")
					logger.error err: error, doc_id: doc_id, project_id: project_id, "inconsistent doc versions"
					# Push the update back into Mongo - catching errors at this
					# point is useless, we're already bailing
					MongoManager.insertCompressedUpdates project_id, doc_id, [lastCompressedUpdate], () ->
						return callback error
					return

			compressedUpdates = UpdateCompressor.compressRawUpdates lastCompressedUpdate, rawUpdates
			MongoManager.insertCompressedUpdates project_id, doc_id, compressedUpdates, (error) ->
				return callback(error) if error?
				logger.log project_id: project_id, doc_id: doc_id, rawUpdatesLength: length, compressedUpdatesLength: compressedUpdates.length, "compressed doc updates"
				callback()

	REDIS_READ_BATCH_SIZE: 100
	processUncompressedUpdates: (project_id, doc_id, callback = (error) ->) ->
		RedisManager.getOldestRawUpdates doc_id, UpdatesManager.REDIS_READ_BATCH_SIZE, (error, rawUpdates) ->
			return callback(error) if error?
			length = rawUpdates.length
			UpdatesManager.compressAndSaveRawUpdates project_id, doc_id, rawUpdates, (error) ->
				return callback(error) if error?
				logger.log project_id: project_id, doc_id: doc_id, "compressed and saved doc updates"
				RedisManager.deleteOldestRawUpdates doc_id, length, (error) ->
					return callback(error) if error?
					if length == UpdatesManager.REDIS_READ_BATCH_SIZE
						# There might be more updates
						logger.log project_id: project_id, doc_id: doc_id, "continuing processing updates"
						setTimeout () ->
							UpdatesManager.processUncompressedUpdates project_id, doc_id, callback
						, 0
					else
						logger.log project_id: project_id, doc_id: doc_id, "all raw updates processed"
						callback()

	processUncompressedUpdatesWithLock: (project_id, doc_id, callback = (error) ->) ->
		LockManager.runWithLock(
			"HistoryLock:#{doc_id}",
			(releaseLock) ->
				UpdatesManager.processUncompressedUpdates project_id, doc_id, releaseLock
			callback
		)

	getDocUpdates: (project_id, doc_id, options = {}, callback = (error, updates) ->) ->
		UpdatesManager.processUncompressedUpdatesWithLock project_id, doc_id, (error) ->
			return callback(error) if error?
			MongoManager.getDocUpdates doc_id, options, callback

	getDocUpdatesWithUserInfo: (project_id, doc_id, options = {}, callback = (error, updates) ->) ->
		UpdatesManager.getDocUpdates project_id, doc_id, options, (error, updates) ->
			return callback(error) if error?
			UpdatesManager.fillUserInfo updates, (error, updates) ->
				return callback(error) if error?
				callback null, updates

	getProjectUpdates: (project_id, options = {}, callback = (error, updates) ->) ->
		MongoManager.getProjectUpdates project_id, options, callback

	getProjectUpdatesWithUserInfo: (project_id, options = {}, callback = (error, updates) ->) ->
		UpdatesManager.getProjectUpdates project_id, options, (error, updates) ->
			return callback(error) if error?
			UpdatesManager.fillUserInfo updates, (error, updates) ->
				return callback(error) if error?
				callback null, updates

	getSummarizedProjectUpdates: (project_id, options = {}, callback = (error, updates) ->) ->
		options.min_count ||= 25
		summarizedUpdates = []
		before = options.before
		do fetchNextBatch = () ->
			UpdatesManager._extendBatchOfSummarizedUpdates project_id, summarizedUpdates, before, options.min_count, (error, updates, nextBeforeUpdate) ->
				return callback(error) if error?
				if !nextBeforeUpdate? or updates.length >= options.min_count
					callback null, updates, nextBeforeUpdate
				else
					before = nextBeforeUpdate
					summarizedUpdates = updates
					fetchNextBatch()

	_extendBatchOfSummarizedUpdates: (
		project_id,
		existingSummarizedUpdates,
		before, desiredLength,
		callback = (error, summarizedUpdates, endOfDatabase) ->
	) ->
		UpdatesManager.getProjectUpdatesWithUserInfo project_id, { before: before, limit: 3 * desiredLength }, (error, updates) ->
			return callback(error) if error?

			# Suppose in this request we have fetch the solid updates. In the next request we need
			# to fetch the dotted updates. These are defined by having an end timestamp less than
			# the last update's end timestamp (updates are ordered by descending end_ts). I.e.
			#                 start_ts--v       v--end_ts
			#   doc1: |......|  |...|   |-------|
			#   doc2:     |------------------|
			#                                ^----- Next time, fetch all updates with an
			#                                       end_ts less than this
			#          
			if updates? and updates.length > 0
				nextBeforeTimestamp = updates[updates.length - 1].meta.end_ts
			else
				nextBeforeTimestamp = null

			summarizedUpdates = UpdatesManager._summarizeUpdates(
				updates, existingSummarizedUpdates
			)
			callback null,
				summarizedUpdates,
				nextBeforeTimestamp

	fillUserInfo: (updates, callback = (error, updates) ->) ->
		users = {}
		for update in updates
			if UpdatesManager._validUserId(update.meta.user_id)
				users[update.meta.user_id] = true

		jobs = []
		for user_id, _ of users
			do (user_id) ->
				jobs.push (callback) ->
					WebApiManager.getUserInfo user_id, (error, userInfo) ->
						return callback(error) if error?
						users[user_id] = userInfo
						callback()

		async.series jobs, (error) ->
			return callback(error) if error?
			for update in updates
				user_id = update.meta.user_id
				delete update.meta.user_id
				if UpdatesManager._validUserId(user_id)
					update.meta.user = users[user_id]
			callback null, updates

	_validUserId: (user_id) ->
		if !user_id?
			return false
		else
			return !!user_id.match(/^[a-f0-9]{24}$/)


	TIME_BETWEEN_DISTINCT_UPDATES: fiveMinutes = 5 * 60 * 1000
	_summarizeUpdates: (updates, existingSummarizedUpdates = []) ->
		summarizedUpdates = existingSummarizedUpdates.slice()
		for update in updates
			earliestUpdate = summarizedUpdates[summarizedUpdates.length - 1]
			if earliestUpdate and earliestUpdate.meta.start_ts - update.meta.end_ts < @TIME_BETWEEN_DISTINCT_UPDATES
				if update.meta.user?
					userExists = false
					for user in earliestUpdate.meta.users
						if user.id == update.meta.user.id
							userExists = true
							break
					if !userExists
						earliestUpdate.meta.users.push update.meta.user

				if update.doc_id.toString() not in earliestUpdate.doc_ids
					earliestUpdate.doc_ids.push update.doc_id.toString()

				earliestUpdate.meta.start_ts = Math.min(earliestUpdate.meta.start_ts, update.meta.start_ts)
				earliestUpdate.meta.end_ts   = Math.max(earliestUpdate.meta.end_ts, update.meta.end_ts)
				earliestUpdate.fromV = update.v
			else
				newUpdate =
					meta:
						users: []
						start_ts: update.meta.start_ts
						end_ts: update.meta.end_ts
					fromV: update.v
					toV: update.v
					doc_ids: [update.doc_id.toString()]

				if update.meta.user?
					newUpdate.meta.users.push update.meta.user

				summarizedUpdates.push newUpdate

		return summarizedUpdates

