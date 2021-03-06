strInject = (s1, pos, s2) -> s1[...pos] + s2 + s1[pos..]
strRemove = (s1, pos, length) -> s1[...pos] + s1[(pos + length)..]

module.exports = UpdateCompressor =
	NOOP: "noop"

	# Updates come from the doc updater in format
	# {
	# 	op:   [ { ... op1 ... }, { ... op2 ... } ]
	# 	meta: { ts: ..., user_id: ... }
	# }
	# but it's easier to work with on op per update, so convert these updates to
	# our compressed format
	# [{
	# 	op: op1
	# 	meta: { start_ts: ... , end_ts: ..., user_id: ... }
	# }, {
	# 	op: op2
	# 	meta: { start_ts: ... , end_ts: ..., user_id: ... }
	# }]
	convertToSingleOpUpdates: (updates) ->
		splitUpdates = []
		for update in updates
			if update.op.length == 0
				splitUpdates.push
					op: UpdateCompressor.NOOP
					meta:
						start_ts: update.meta.start_ts or update.meta.ts
						end_ts:   update.meta.end_ts   or update.meta.ts
						user_id:  update.meta.user_id
					v: update.v
			else
				for op in update.op
					splitUpdates.push
						op: op
						meta:
							start_ts: update.meta.start_ts or update.meta.ts
							end_ts:   update.meta.end_ts   or update.meta.ts
							user_id:  update.meta.user_id
						v: update.v
		return splitUpdates

	concatUpdatesWithSameVersion: (updates) ->
		concattedUpdates = []
		for update in updates
			lastUpdate = concattedUpdates[concattedUpdates.length - 1]
			if lastUpdate? and lastUpdate.v == update.v
				lastUpdate.op.push update.op unless update.op == UpdateCompressor.NOOP
			else
				nextUpdate =
					op:   []
					meta: update.meta
					v:    update.v
				nextUpdate.op.push update.op unless update.op == UpdateCompressor.NOOP
				concattedUpdates.push nextUpdate
		return concattedUpdates

	compressRawUpdates: (lastPreviousUpdate, rawUpdates) ->
		if lastPreviousUpdate?.op?.length > 1
			# if the last previous update was an array op, don't compress onto it.
			# The avoids cases where array length changes but version number doesn't
			return [lastPreviousUpdate].concat UpdateCompressor.compressRawUpdates(null,rawUpdates)
		if lastPreviousUpdate?
			rawUpdates = [lastPreviousUpdate].concat(rawUpdates)
		updates = UpdateCompressor.convertToSingleOpUpdates(rawUpdates)
		updates = UpdateCompressor.compressUpdates(updates)
		return UpdateCompressor.concatUpdatesWithSameVersion(updates)

	compressUpdates: (updates) ->
		return [] if updates.length == 0

		compressedUpdates = [updates.shift()]
		for update in updates
			lastCompressedUpdate = compressedUpdates.pop()
			if lastCompressedUpdate?
				compressedUpdates = compressedUpdates.concat UpdateCompressor._concatTwoUpdates lastCompressedUpdate, update
			else
				compressedUpdates.push update

		return compressedUpdates

	MAX_TIME_BETWEEN_UPDATES: oneMinute = 60 * 1000
	MAX_UPDATE_SIZE: twoMegabytes = 2* 1024 * 1024

	_concatTwoUpdates: (firstUpdate, secondUpdate) ->
		firstUpdate =
			op: firstUpdate.op
			meta:
				user_id:  firstUpdate.meta.user_id or null
				start_ts: firstUpdate.meta.start_ts or firstUpdate.meta.ts
				end_ts:   firstUpdate.meta.end_ts   or firstUpdate.meta.ts
			v: firstUpdate.v
		secondUpdate =
			op: secondUpdate.op
			meta:
				user_id:  secondUpdate.meta.user_id or null
				start_ts: secondUpdate.meta.start_ts or secondUpdate.meta.ts
				end_ts:   secondUpdate.meta.end_ts   or secondUpdate.meta.ts
			v: secondUpdate.v

		if firstUpdate.meta.user_id != secondUpdate.meta.user_id
			return [firstUpdate, secondUpdate]

		if secondUpdate.meta.start_ts - firstUpdate.meta.end_ts > UpdateCompressor.MAX_TIME_BETWEEN_UPDATES
			return [firstUpdate, secondUpdate]

		firstOp = firstUpdate.op
		secondOp = secondUpdate.op

		firstSize = firstOp.i?.length or firstOp.d?.length
		secondSize = secondOp.i?.length or secondOp.d?.length

		# Two inserts
		if firstOp.i? and secondOp.i? and firstOp.p <= secondOp.p <= (firstOp.p + firstOp.i.length) and firstSize + secondSize < UpdateCompressor.MAX_UPDATE_SIZE
			return [
				meta:
					start_ts: firstUpdate.meta.start_ts
					end_ts:   secondUpdate.meta.end_ts
					user_id:  firstUpdate.meta.user_id
				op:
					p: firstOp.p
					i: strInject(firstOp.i, secondOp.p - firstOp.p, secondOp.i)
				v: secondUpdate.v
			]
		# Two deletes
		else if firstOp.d? and secondOp.d? and secondOp.p <= firstOp.p <= (secondOp.p + secondOp.d.length) and firstSize + secondSize < UpdateCompressor.MAX_UPDATE_SIZE
			return [
				meta:
					start_ts: firstUpdate.meta.start_ts
					end_ts:   secondUpdate.meta.end_ts
					user_id:  firstUpdate.meta.user_id
				op:
					p: secondOp.p
					d: strInject(secondOp.d, firstOp.p - secondOp.p, firstOp.d)
				v: secondUpdate.v
			]
		# An insert and then a delete
		else if firstOp.i? and secondOp.d? and firstOp.p <= secondOp.p <= (firstOp.p + firstOp.i.length)
			offset = secondOp.p - firstOp.p
			insertedText = firstOp.i.slice(offset, offset + secondOp.d.length)
			# Only trim the insert when the delete is fully contained within in it
			if insertedText == secondOp.d
				insert = strRemove(firstOp.i, offset, secondOp.d.length)
				return [
					meta:
						start_ts: firstUpdate.meta.start_ts
						end_ts:   secondUpdate.meta.end_ts
						user_id:  firstUpdate.meta.user_id
					op:
						p: firstOp.p
						i: insert
					v: secondUpdate.v
				]
			else
				# This will only happen if the delete extends outside the insert
				return [firstUpdate, secondUpdate]

		else
			return [firstUpdate, secondUpdate]

