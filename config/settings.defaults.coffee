module.exports =
	mongo:
		url: 'mongodb://127.0.0.1/sharelatex'
	internal:
		trackchanges:
			port: 3015
			host: "localhost"
	apis:
		documentupdater:
			url: "http://localhost:3003"
		docstore:
			url: "http://localhost:3016"
		web:
			url: "http://localhost:3000"
			user: "sharelatex"
			pass: "password"
	redis:
		web:
			host: "localhost"
			port: 6379
			pass: ""

	#filestore:
	#	backend: "s3"
	#	stores:
	#		user_files: "sharelatex-dev"
	#	s3:
	#		key: ""
	#		secret: ""
