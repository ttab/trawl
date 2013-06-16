program = require 'commander'
ProgressBar = require 'progress'
pckage = require './package.json'
ESLight = require 'eslight'
url = require 'url'

program
.version(pckage.version)
.usage('[options] <url>')
.option('-r, --recent [num]', 'Number of recent posts [100]', 100)
.option('-n, --nth [num]', 'After recent posts, grab every nth post [10]', 10)
.parse(process.argv)

if program.args.length != 1
    console.error 'ERROR: Requires one elastic url argument'
    program.outputHelp()
    process.exit(1)

host = url.parse program.args[0]

if not host.path.match /\/.+?\/.+?/
    console.error 'ERROR: Expect elastic url to contain index/type'
    program.outputHelp()
    process.exit(1)

es = new ESLight host

SIZE = 100
bar = null

(es.exec host.pathname, '_search', {scroll:'1m',size:SIZE},
    {query:{match_all:{}},sort:{createdDateTime:{order:'desc'}}})
.then (res) ->
    bar = new ProgressBar('  trawling [:bar] :percent (:current/:total)',
        {total:res.hits.total, width: 40, complete:'=', incomplete:' '})
    scroll = (scrollId) ->
        (es.exec '_search/scroll', {scroll:'1m',size:SIZE,scroll_id:scrollId}, null).then (res) ->
            bag res.hits.total, res.hits.hits
            scroll res._scroll_id
    bag res.hits.total, res.hits.hits
    scroll res._scroll_id
.done()

bag = (total, hits) ->

    bar.tick hits.length
