stream = require 'stream'
events = require 'events'
Q = require 'q'

class LineStream extends events.EventEmitter

    constructor: (src, encoding) ->
        throw new Error('Must wrap a stream.Readable') if src not instanceof stream.Readable
        @src = src
        @encoding = encoding ? 'utf-8'
        @buffers = []
        @lines = []
        @defs = []
        events.EventEmitter.call this
        src.on 'readable', => @_consume false
        src.on 'end', => @_consume true; this.emit 'end'
        src.on 'error', => this.emit 'error', arguments

    _consume: (streamEnd) ->
        @buffers.push newbuf while newbuf = @src.read()
        return 0 if not @buffers.length
        0 while @_makeline(streamEnd)
        @defs.shift()._fillup() while @defs.length and (@lines.length or streamEnd)
        this.emit 'readable' if @lines.length
        return @lines.length

    _makeline: (streamEnd) ->
        found = 0
        line = []
        while @buffers.length
            str = @buffers.shift().toString @encoding
            beg = end = 0
            while beg < str.length
                end++ while end < str.length and (cur = str.charAt(end)) != '\n'
                adj = if end > 0 and str.charAt(end - 1) == '\r' then -1 else 0
                line.push (str.substring beg, end + adj)
                beg = ++end
                if end < str.length and cur == '\n'
                    @lines.push line.join('')
                    line = []
                    found++
        if line.length
            if streamEnd
                @lines.push line.join('')
                found++
            else
                @buffers.unshift line.join('')
        return found

    read: (amount) ->
        return null if not @lines.length
        return @lines.splice 0, amount

    readPromise: (amount) ->
        def = Q.defer()
        def._fillup = => def.resolve (if @lines.length then @lines.splice 0, amount else null)
        if @lines.length then def._fillup() else @defs.push def
        return def.promise

    pause: ->
        @src.pause()

    resume: ->
        @src.resume()

module.exports = LineStream
