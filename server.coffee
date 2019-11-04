express = require 'express'
compression = require 'compression'
snap = require './snap'
Cacheman = require 'cacheman'

server_url = process.env.SERVER_URL
if not server_url
	process.exit(3)

error = (e, res) =>
	console.error e
	info = e && (e.status or e.msg or e.message or e.result) or 'no error message available';
	if res
		res.status(500).send "Request failed: " + e

app = express()

app.use compression( filter: (req, res) =>
	if req.headers['x-no-compression']
		return false
	compression.filter req, res
)

app.use '/howto', express.static('howto')

cache = new Cacheman
	ttl: 60*30
	delimiter: '-'
	engine: 'file'
	tmpDir: 'cache'

app.get '/', (req, res, next) =>
	{ url, width, height, scroll_top, links } = req.query
	# some q&d params parsing #
	if not url then return res.status(422).send "query param url missing. see #{server_url}/howto"
	if not url.match /^http/
		url = "http://#{url}"
	width = Number width
	if Number.isNaN(width) then return res.status(422).send "query param width missing. see #{server_url}/howto"
	height = Number height
	if Number.isNaN(height) then return res.status(422).send "query param height missing. see #{server_url}/howto"
	scroll_top = Number scroll_top
	if Number.isNaN(scroll_top) then scroll_top = 0
	links = links == "on" or links == true or links == "true" or links == 1 or links == "1"

	cache_key = [ url, width, height, scroll_top, links ]
	cached = await cache.get cache_key
	if cached
		return res.send cached

	try
		html = await snap server_url, url, width, height, scroll_top, links
		await cache.set cache_key, html
		res.send html
	catch e
		error e, res

app.use (err, req, res, next) =>
    error err, res

process.on 'unhandledRejection', (reason, p) =>
	error "UHPRJ @ #{p}, #{reason}"

do =>
    app.listen 8080, => console.log 'running'