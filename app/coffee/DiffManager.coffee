HistoryManager = require "./HistoryManager"
DocumentUpdaterManager = require "./DocumentUpdaterManager"
MongoManager = require "./MongoManager"
DiffGenerator = require "./DiffGenerator"
logger = require "logger-sharelatex"

module.exports = DiffManager =
	getLatestDocAndUpdates: (project_id, doc_id, fromDate, toDate, callback = (error, lines, version, updates) ->) ->
		HistoryManager.processUncompressedUpdatesWithLock doc_id, (error) ->
			return callback(error) if error?
			DocumentUpdaterManager.getDocument project_id, doc_id, (error, lines, version) ->
				return callback(error) if error?
				MongoManager.getUpdatesBetweenDates doc_id, fromDate, toDate, (error, updates) ->
					return callback(error) if error?
					callback(null, lines, version, updates)
	
	getDiff: (project_id, doc_id, fromDate, toDate, callback = (error, diff) ->) ->
		logger.log project_id: project_id, doc_id: doc_id, from: fromDate, to: toDate, "getting diff"
		DiffManager.getLatestDocAndUpdates project_id, doc_id, fromDate, null, (error, lines, version, updates) ->
			return callback(error) if error?

			logger.log lines: lines, version: version, updates: updates, "got doc and updates"

			lastUpdate = updates[0]
			if lastUpdate? and lastUpdate.v != version
				return callback new Error("latest update version, #{lastUpdate.v}, does not match doc version, #{version}")

			updatesToApply = []
			for update in updates.reverse()
				if update.meta.start_ts <= toDate
					updatesToApply.push update

			logger.log project_id: project_id, doc_id: doc_id, updatesToApply: updatesToApply, "got updates to apply"

			try
				startingContent = DiffGenerator.rewindUpdates lines.join("\n"), updates
				logger.log project_id: project_id, doc_id: doc_id, startingContent: startingContent, "rewound doc"
				diff = DiffGenerator.buildDiff startingContent, updatesToApply
			catch e
				return callback(e)
			
			callback(null, diff)