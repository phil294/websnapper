puppeteer = require('puppeteer')
fs = require('fs')

################################################################################
url = 'https://reddit.com'
viewport =
	width: 800
	height: 600
scroll_top = 0
anchor_links = true
################################################################################

dewwit = =>
	browser = await puppeteer.launch()
	page = await browser.newPage()
	page.setViewport viewport
	page.setJavaScriptEnabled false
	page.setRequestInterception true
	page.on 'request', (req) =>
		if ['image', 'media', 'font'].includes req.resourceType()
			return req.abort()
		req.continue()
	await page.goto url,
		timeout: 15000
	
	if scroll_top
		await page.evaluate (scroll_top) =>
			window.scrollBy 0, scroll_top
		, scroll_top

	await page.screenshot({path: 'blub.png'});

	# is necessary (bug?) because
	# the below node filtering cannot be run with javascript enabled, failing with
	# Error: Evaluation failed: Error:
	# 	Failed to execute 'acceptNode' on 'NodeFilter':
	# 	The provided callback is no longer runnable.
	page.setJavaScriptEnabled true
	# so JS will still not be executed
	await page.evaluate => debugger
	
	absolute_els = await page.evaluate (anchor_links) =>
		escapeHtml = (t) => t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#039;")
		els = []
		in_viewport = (rect) =>
			rect.top < window.innerHeight and rect.bottom >= 0
		occupied_rects = []
		get_style = (rect) =>
			top = Math.round rect.top
			bottom = Math.round rect.bottom
			left = Math.round rect.left
			right = Math.round rect.right
			# html like `<div>my <i>name</i> is</div>` consists out of three
			# different text nodes. the bounding client rects would now overlap.
			# fix this by simply moving stuff further down.
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
			if anchor_links
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
					els.push "<a style='#{style}' href='#{node.href}'>#{content}</a>"
		els
	, anchor_links

	html = """
		<style>
			main{
				background:#f6f6f6;
				width:#{viewport.width}px;
				height:#{viewport.height}px;
			}
			main *{
				position:absolute;
				font:x-small sans;
			}
			.img{
				display:flex;
				justify-content:center;
				align-items:center;
				border:1px dotted gray;
			}
		</style>
	""".replace(/[\n\t]/g,'') + """
	\n<p>compression rate, homepage, options
	<main>#{absolute_els.join("")}</main>
	"""
	
	fs.writeFileSync '/b/testi.html', html

	await browser.close()

do =>
	try
		await dewwit()
	catch e
		console.error e
		process.exit(1)
	process.exit(0)