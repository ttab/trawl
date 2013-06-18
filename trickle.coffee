program = require 'commander'
ProgressBar = require 'progress'
pckage = require './package.json'
ESLight = require 'eslight'
url = require 'url'
fs = require 'fs'
http = require 'http'
Q = require 'q'
path = require 'path'
querys = require 'querystring'
spawn = require('child_process').spawn

program
.version(pckage.version)
.usage('[options] <index/type>')
.option('-e, --elastic [host]', 'Elasticsearch instance [http://192.168.33.10:9200/]',
    'http://192.168.33.10:9200/')
.option('-a, --asset-host [host]', 'URL to the host serving assets [http://192.168.33.10/]',
    'http://192.168.33.10/')
.option('-w, --www-root [path]', 'File system path to move the downloaded assets',
    '/var/scampi')
.option('-q, --quiet', 'No output', false)
.parse(process.argv)

if program.args.length != 1
    console.error 'ERROR: Requires a index/type such as: images/sgb'
    program.outputHelp()
    process.exit(1)

split = program.args[0].split '/'
if split.length != 2
    console.error 'ERROR: Requires a index/type such as: images/sgb'
    program.outputHelp()
    process.exit(1)

index = split[0]
type = split[1]
classifier = index + '_' + type

ehost = url.parse program.elastic
ahost = url.parse program.assetHost

es = new ESLight ehost

nexus = 'http://spix-core01.driften.net:8081/nexus/service/local/artifact/maven/content?'


mkdirp = (dir) ->
    return if dir == '.' or dir == '/'
    left = path.dirname dir
    mkdirp left
    fs.mkdirSync dir if !(fs.existsSync dir)

query = {
    g: 'se.prb',
    a: 'scanpix-trawl',
    v: '1.0.0-SNAPSHOT',
    r: 'snapshots',
    c: classifier,
    e: 'zip'
    }

nurl = nexus + querys.stringify(query)
opts = url.parse nurl

#scanpix-trawl-1.0.0-20130618.072327-4-images_sgb.zip

checkOrigin = ->
    def = Q.defer()
    opts.method = 'HEAD'
    req = http.request opts, (res) ->
        filename = res.headers['content-disposition']
        filename = (filename.match /.*filename=\"(.+?)\".*/)[1]
        file = __dirname + '/target/' + filename
        size = parseInt res.headers['content-length'], 10
        def.resolve([filename, file, size])
        req.abort() # HEAD hangs for some reaons
        res.on 'error', (err) -> throw err; def.reject(err)
    req.on 'error', (err) -> throw err; def.reject(err)
    req.end()
    def.promise

checkOrigin().then (args) ->
    [filename, file, size] = args
    upToDate = (if fs.existsSync file then (fs.statSync file).size == size)
    if upToDate
        console.log 'Already downloaded.' if !program.quiet
        return Q(file)
    else
        console.log 'Downloading...' if !program.quiet
        def = Q.defer()
        bar = null
        if !program.quiet
            bar = new ProgressBar('  fetching [:bar] :percent (:current/:total)',
                {total:size, width: 40, complete:'=', incomplete:' '})
        opts.method = 'GET'
        http.get opts, (res) ->
            mkdirp (path.basename file)
            ws = fs.createWriteStream file, {mode:'0644'}
            rwrite = ws.write
            ws.write = (buf) ->
                bar.tick buf.length if !program.quiet
                rwrite.apply this, arguments
            res.pipe ws
            res.on 'end', -> req.abort(); def.resolve file
        return def.promise
.then (file) ->
    def = Q.defer()
    unzipTo = __dirname + '/target/' + classifier
    console.log 'Unzipping...' if !program.quiet
    mkdirp unzipTo
    unzip = spawn 'unzip', ['-qq', '-o', file], {cwd:unzipTo}
    unzip.stdout.on 'data', -> console.log arguments
    unzip.stderr.on 'data', -> console.log arguments
    unzip.on 'close', (code) ->
        throw 'unzip failed: ' + code if code != 0
    def.resolve unzipTo
    def.promise
.then (dir) ->
    console.log 'Deleting previous type.' if !program.quiet
    (es.exec 'DELETE', index, type).then (res) ->
        if res.status == 404 or res.ok then dir
.then (dir) ->
    console.log 'Creating mapping.' if !program.quiet
    mapping = fs.readFileSync dir + '/mapping_' + classifier + '.json', {encoding: 'utf-8'}
    mapping = JSON.parse(mapping)
    (es.exec 'POST', index, type, '_mapping', mapping).then (res) ->
        if res.status then dir
.then (dir) ->
    console.log 'Uploading dump...' if !program.quiet
    dump = fs.readFileSync dir + '/dump_' + classifier + '.txt', {encoding: 'utf-8'}
    assetReplace = ahost.href.substring 0, ahost.href.length - 1
    dump = new Buffer(dump.replace /\$\$\$ASSET_HOST\$\$\$/g, assetReplace)
    (es.exec 'POST', '_bulk', dump).then (res) ->
        if res.status then dir
.then (dir) ->
    console.log dir
.done()

#?g=se.prb&a=#{artifactName}&v=#{node['scanpix']['version']}&r=#{node['scanpix']['nexus']['repository']}&c=bin&e=zip'
