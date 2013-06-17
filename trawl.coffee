program = require 'commander'
ProgressBar = require 'progress'
pckage = require './package.json'
ESLight = require 'eslight'
url = require 'url'
fs = require 'fs'
http = require 'http'
Q = require 'q'
path = require 'path'

program
.version(pckage.version)
.usage('[options] <url>')
.option('-r, --recent [num]', 'Number of recent posts [100]', Number, 100)
.option('-n, --nth [num]', 'After recent posts, grab every nth post [10]', Number, 10)
.option('-m, --max [num]', 'Maximum number of posts to scan [3000]', Number, 3000)
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

# mkdir -p
mkdirp = (dir) ->
    return if dir == '.' or dir == '/'
    left = path.dirname dir
    mkdirp left
    fs.mkdirSync dir if !(fs.existsSync dir)


fileOpts = {encoding:'utf-8', mode:'0644'}
dumpDir = __dirname + '/dump'
outputDir = __dirname + '/target'
mkdirp dumpDir
mkdirp outputDir
indexType = host.pathname.substring(1).replace('/', '_')
dumpFileName = 'dump_' + indexType + '.txt'
dumpWs = fs.createWriteStream dumpDir + '/' + dumpFileName, fileOpts
mappingFileName = 'mapping_' + indexType + '.json'
mappingWs = fs.createWriteStream dumpDir + '/' + mappingFileName, fileOpts
archiveFileName = indexType + '.zip'
archiveWs = fs.createWriteStream outputDir + '/' + archiveFileName, {mode:'0644'}

SIZE = 100
bar = null

mapping = ->
    def = Q.defer()
    console.log 'Saving mapping'
    (es.exec host.pathname, '_mapping', {pretty:true}, null)
    .then (res) ->
        if res.status != 200
            console.error "Bad response", res
            process.exit(1)
        delete res.status
        mappingWs.end JSON.stringify(res) + '\n'
        def.resolve()
    .done()
    def.promise

trawl = ->
    def = Q.defer()
    console.log 'Trawling through posts'
    (es.exec host.pathname, '_search', {scroll:'1m',size:SIZE},
        {query:{match_all:{}},sort:{createdDateTime:{order:'desc'}}})
    .then (res) ->
        total = if program.max > 0 then program.max else res.hits.total
        bar = new ProgressBar('  trawling [:bar] :percent (:current/:total)',
            {total:total, width: 40, complete:'=', incomplete:' '})
        scroll = (scrollId) ->
            (es.exec '_search/scroll', {scroll:'1m',size:SIZE,scroll_id:scrollId}, null)
            .then (res) ->
                bag res.hits.hits
                if bar.curr < program.max
                    scroll res._scroll_id
                else
                    dumpWs.end()
                    def.resolve()
        bag res.hits.hits
        scroll res._scroll_id
    .done()
    def.promise


bag = (hits) ->
    hits.forEach (hit) ->
        if bar.curr < program.recent or bar.curr % program.nth == 0
            header = {index:{_index:hit._index,_type:hit._type,_id:hit._id}}
            dumpWs.write JSON.stringify(header)+ '\n'
            # this rewrites the asset urls
            bagAssets hit._source.assets
            dumpWs.write JSON.stringify(hit._source) + '\n'
        bar.tick()

# token to insert for the asset host, replaced when installing
# the dump using 'tickle' command
rewriteAssetHost = '$$$ASSET_HOST$$$'
todoAssets = []

bagAssets = (assets) ->
    return if !assets
    for asset in assets
        continue if not asset.url
        sourceUrl = asset.url
        assUrl = url.parse sourceUrl
        output = dumpDir + '/assets' + assUrl.pathname
        outdir = path.dirname output
        mkdirp outdir
        # deliberately rewrite original asset ref for output
        asset.url = rewriteAssetHost + assUrl.pathname
        fileOut = null
        todoAssets.push {source:sourceUrl, output:output}

WORKERS = 10

downloadAssets = ->
    console.log '\nDownloading assets'
    bar = new ProgressBar('    assets [:bar] :percent (:current/:total)',
        {total:todoAssets.length, width: 40, complete:'=', incomplete:' '})
    perWorker = Math.ceil(todoAssets.length / WORKERS)

    consume = ->
        queue = todoAssets.splice 0, perWorker
        queue.reduce (prev, cur) ->
            def = Q.defer()
            prev.then -> http.get cur.source, (res) ->
                res.pipe (fs.createWriteStream cur.output, {mode:'0644'})
                res.on 'end', -> def.resolve(); bar.tick()
            def.promise
        , Q()

    todo = (consume() for i in [1..WORKERS])
    return Q.all todo

archiver = require 'archiver'


recurse = (base, path, cur, apply, prev) ->
    prev = prev ? Q()
    fullPath = base + '/' + path.join('/') + '/' + cur
    stat = fs.statSync fullPath
    prom = null
    if stat.isDirectory()
        def = Q.defer()
        fs.readdir fullPath, (err, files) ->
            throw err if err
            newPath = path.slice 0
            newPath.push cur
            waitFor = (tmp = recurse base, newPath, file, apply, tmp for file in files)
            def.resolve(Q.all waitFor)
        prom = def.promise
    else if stat.isFile()
        prom = apply fullPath, path, cur, prev
    return prom


compress = ->
    cdef = Q.defer()
    console.log '\nCompressing'
    archive = archiver 'zip'
    archive.on 'error', (err) -> throw err
    archive.pipe archiveWs
    total = 0
    (recurse dumpDir, [], '', -> total++)
    .then ->
        bar = new ProgressBar('  archiving [:bar] :percent (:current/:total)',
            {total:total, width: 40, complete:'=', incomplete:' '})
    .then ->
        recurse dumpDir, [], '', (full, path, cur, prev) ->
            prev.then ->
                def = Q.defer()
                archive.append fs.createReadStream(full), {name:path.join('/') + '/' + cur}, (err) ->
                    throw err if err
                    bar.tick()
                    def.resolve()
                def.promise
    .then ->
        archive.finalize (err, written) ->
            throw err if err
            console.log '\nWritten', written, 'bytes:', outputDir + '/' + archiveFileName
        archiveWs.end()
        cdef.resolve()
    cdef.promise

# workflow
mapping()
.then -> trawl()
.then -> downloadAssets()
.then -> compress()
.then ->
    console.log 'Done.'
    process.exit(0)
.done()
