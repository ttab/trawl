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
.usage('[options] <zip archive>')
.option('-r, --recent [num]', 'Number of recent posts [50]', Number, 50)
.option('-n, --nth [num]', 'After recent posts, grab every nth post [500]', Number, 500)
.option('-m, --max [num]', 'Maximum number of posts to scan, 0 for all [0]', Number, 0)
.parse(process.argv)
