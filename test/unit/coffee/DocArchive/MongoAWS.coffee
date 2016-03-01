chai = require('chai')
chai.should()
sinon = require("sinon")
modulePath = "../../../../app/js/MongoAWS.js"
SandboxedModule = require('sandboxed-module')
{ObjectId} = require("mongojs")

describe "MongoAWS", ->
	beforeEach ->
		@MongoAWS = SandboxedModule.require modulePath, requires:
			"settings-sharelatex": @settings =
				trackchanges:
					s3:
						secret: "s3-secret"
						key: "s3-key"
					stores:
						doc_history: "s3-bucket"
			"child_process": @child_process = {}
			"mongo-uri": @mongouri = {}
			"logger-sharelatex": @logger = {log: sinon.stub(), error: sinon.stub(), err:->}
			"aws-sdk": @awssdk = {}
			"fs": @fs = {}
			"s3-streams": @s3streams = {}
			"./mongojs" : { db: @db = {}, ObjectId: ObjectId }
			"JSONStream": @JSONStream = {}
			"readline-stream": @readline = sinon.stub()

		@project_id = ObjectId().toString()
		@doc_id = ObjectId().toString()
		@update = { v:123 }
		@callback = sinon.stub()
		
	# describe "archiveDocHistory", ->

	# 	beforeEach ->
	# 		@awssdk.config = { update: sinon.stub() } 
	# 		@awssdk.S3 = sinon.stub()
	# 		@s3streams.WriteStream = sinon.stub()
	# 		@db.docHistory = {}
	# 		@db.docHistory.on = sinon.stub()
	# 		@db.docHistory.find = sinon.stub().returns @db.docHistory
	# 		@db.docHistory.on.returns
	# 			pipe:->
	# 				pipe:->
	# 					on: (type, cb)-> 
	# 						on: (type, cb)-> 
	# 							cb()
	# 		@JSONStream.stringify = sinon.stub()

	# 		@MongoAWS.archiveDocHistory @project_id, @doc_id, @update, @callback

	# 	it "should call the callback", ->
	# 		@callback.called.should.equal true

	# describe "unArchiveDocHistory", ->

	# 	beforeEach ->
	# 		@awssdk.config = { update: sinon.stub() } 
	# 		@awssdk.S3 = sinon.stub()
	# 		@s3streams.ReadStream = sinon.stub()

	# 		@s3streams.ReadStream.returns
	# 			#describe on 'open' behavior
	# 			on: (type, cb)->
	# 				#describe on 'error' behavior
	# 				on: (type, cb)->
	# 					pipe:->
	# 						#describe on 'data' behavior
	# 						on: (type, cb)->
	# 							cb([])
	# 							#describe on 'end' behavior
	# 							on: (type, cb)-> 
	# 								cb()
	# 								#describe on 'error' behavior
	# 								on: sinon.stub()

	# 		@MongoAWS.handleBulk = sinon.stub()
	# 		@MongoAWS.unArchiveDocHistory @project_id, @doc_id, @callback

	# 	it "should call handleBulk", ->
	# 		@MongoAWS.handleBulk.called.should.equal true

	# describe "handleBulk", ->
	# 	beforeEach ->
	# 		@bulkOps = [{
	# 			_id: ObjectId()
	# 			doc_id: ObjectId()
	# 			project_id: ObjectId()
	# 		}, {
	# 			_id: ObjectId()
	# 			doc_id: ObjectId()
	# 			project_id: ObjectId()
	# 		}, {
	# 			_id: ObjectId()
	# 			doc_id: ObjectId()
	# 			project_id: ObjectId()
	# 		}]
	# 		@bulk =
	# 			find: sinon.stub().returns
	# 				upsert: sinon.stub().returns
	# 					updateOne: sinon.stub()
	# 			execute: sinon.stub().callsArgWith(0, null, {})
	# 		@db.docHistory = {}
	# 		@db.docHistory.initializeUnorderedBulkOp = sinon.stub().returns @bulk
	# 		@MongoAWS.handleBulk @bulkOps, @bulkOps.length, @callback

	# 	it "should call updateOne for each operation", ->
	# 		@bulk.find.calledWith({_id:@bulkOps[0]._id}).should.equal true
	# 		@bulk.find.calledWith({_id:@bulkOps[1]._id}).should.equal true
	# 		@bulk.find.calledWith({_id:@bulkOps[2]._id}).should.equal true

	# 	it "should call the callback", ->
	# 		@callback.calledWith(null).should.equal true

