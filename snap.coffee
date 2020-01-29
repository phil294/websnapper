puppeteer = require 'puppeteer'

# Browser stays up all the time. For each request, a new page is created
# and closed afterwards.
browser = null

module.exports = (executable_path = undefined, url, width, height, scroll_top, links, forwarded_for) =>
	if not browser
		browser = await puppeteer.launch
			executablePath: executable_path
			args: [
				'--disable-dev-shm-usage'
			]

	page = await browser.newPage()
	
	page.setJavaScriptEnabled false
	
	page.setViewport { width, height }

	page.setExtraHTTPHeaders
		'Via': 'HTTP 1.1'
		'X-Forwarded-For': forwarded_for
	
	page.setRequestInterception true
	page.on 'request', (req) =>
		if ['image', 'media', 'font'].includes req.resourceType()
			return req.abort()
		req.continue()

	await page.goto url,
		timeout: 7000
	
	if scroll_top
		await page.evaluate (scroll_top) =>
			window.scrollBy 0, scroll_top
		, scroll_top

	#await page.screenshot({path: 'test.png'});

	# reenabling JS (when disabled) is necessary here (bug?) because
	# the below node filtering cannot be run with javascript disabled, failing with
	# Error: Evaluation failed: Error:
	# 	Failed to execute 'acceptNode' on 'NodeFilter':
	# 	The provided callback is no longer runnable.
	page.setJavaScriptEnabled true
	# so JS will still not be executed
	await page.evaluate => debugger
	
	### Get all visible txt, a and img elements converted as absolutely positioned divs ###
	absolute_els = await page.evaluate (links) =>
		els = []
		escapeHtml = (t) => t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#039;")
		in_viewport = (rect) =>
			rect.top < window.innerHeight and rect.bottom >= 0
		occupied_rects = []
		get_style = (rect) =>
			top = Math.round rect.top
			bottom = Math.round rect.bottom
			left = Math.round rect.left
			right = Math.round rect.right
			# html like `<div>my <i>name</i> is</div>` consists out of multiple
			# different text nodes. the bounding client rects would now overlap.
			# fix this by simply moving stuff further down.
			# not beautiful, brow.sh's logic is far better.
			# this also fixes any issues with overlapping elements in general,
			# e.g. accessibility captions
			loop
				occupied_rect = occupied_rects.find (o) =>
					# intersect/overlap?
					o.left <= right and left <= o.right and o.top <= bottom and top <= o.bottom
				if occupied_rect
					new_top = occupied_rect.bottom + 1
					bottom = new_top + (bottom - top)
					top = new_top
				else
					break
			occupied_rects.push { top, left, right, bottom }
			"top:#{top}px;height:#{bottom-top}px;left:#{left}px;width:#{right-left}px;"

		tree_walker = document.createTreeWalker document.body, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT, acceptNode: (node) =>
			if node.offsetParent == null
				return NodeFilter.FILTER_REJECT
			
			rect = node.parentElement.getBoundingClientRect()
			if not in_viewport rect
				return NodeFilter.FILTER_REJECT
			
			special_rendering = [ "IMG" ]
			if links
				special_rendering.push "A"
			if special_rendering.includes node.nodeName
				return NodeFilter.FILTER_ACCEPT
			if special_rendering.includes node.parentElement.nodeName
				return NodeFilter.FILTER_REJECT
			
			if node.nodeType == Node.TEXT_NODE
				return NodeFilter.FILTER_ACCEPT
			
			return NodeFilter.FILTER_SKIP
			
		while tree_walker.nextNode()
			node = tree_walker.currentNode

			if node.nodeType == Node.TEXT_NODE
				content = escapeHtml node.data.trim().replace(/\s{2,}/, ' ')
				if content
					range = document.createRange()
					range.selectNodeContents node
					rects = range.getClientRects()
					if rects.length
						top = Math.min(...[...rects].map (r) => r.top)
						bottom = Math.max(...[...rects].map (r) => r.bottom)
						left = Math.min(...[...rects].map (r) => r.left)
						right = Math.max(...[...rects].map (r) => r.right)
						rect =
							top: top
							left: left
							right: right
							bottom: bottom
					else
						rect = {}
					style = get_style rect
					els.push "<div style='#{style}'>#{content}</div>"
			else if node.nodeName == "IMG"
				alt = node.alt.trim()
				if alt
					style = get_style node.getBoundingClientRect()
					els.push "<div class='img' style='#{style}'>[#{alt}]</div>"
			else if node.nodeName == "A"
				content = escapeHtml node.innerText.trim()
				if content
					style = get_style node.getBoundingClientRect()
					els.push "<a style='#{style}' href='?url=#{encodeURIComponent node.href}&width=#{window.innerWidth}&height=#{window.innerHeight}&links=true'>#{content}</a>"
		els
	, links

	title = await page.title()
	title = "[websnapper] #{title}"

	await page.close()

	# Make a website out of all of this
	# not valid HTML code, but modern browsers will handle this just fine
	html = """
		<meta name="viewport" content="width=device-width, initial-scale=1">
		<title>#{title}</title>
		<style>
			body{
				margin:0;
			}
			main{
				background:#f6f6f6;
				width:#{width}px;
				height:#{height}px;
				position:relative;
				overflow:hidden;
			}
			div,a{
				font:x-small sans;
			}
			main *{
				position:absolute;
			}
			.img{
				display:flex;
				justify-content:center;
				align-items:center;
				border:1px dotted gray;
			}
			.u{
				bottom:30px;
			}
			.i,.u{
				right:20px;
			}
			.i button,.i a,.u button{
				color:red;
			}
		</style>
	""".replace(/[\n\t]/g,'') + """
	\n<main>
	<div class="i"><a href="?url=#{encodeURIComponent url}&width=#{width}&height=#{height}&scroll_top=#{scroll_top-height+100}&links=#{links}"><button>⇡</button></a><br><br><br><a href="/howto">?</a></div>
	#{absolute_els.join("")}
	<a class="u" href="?url=#{encodeURIComponent url}&width=#{width}&height=#{height}&scroll_top=#{scroll_top-100+height}&links=#{links}"><button>⇣</button></a>
	</main>
	"""

	html
