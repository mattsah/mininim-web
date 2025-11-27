import
    mininim,
    mininim/dic,
    mininim/script,
    mininim/web/router,
    checksums/md5,
    std/xmlparser,
    std/parsexml,
    std/xmltree,
    std/streams,
    std/strtabs

export
    xmltree

type
    XmlMode* = enum
        XmlRaw
        XmlEsc
        XmlSec

    XmlTemplate* = ref object of Class
        root: XmlNode
        mode: seq[XmlMode]
        data: seq[dyn] = @[]
        tree: XmlNode = newXmlTree("x", [])
        engine*: XmlEngine

    ElementHook* = proc(tmpl: XmlTemplate, head: XmlNode, node: XmlNode, parent: XmlNode): void

    XmlElement* = ref object of Facet
        name*: string

    AttrFilterHook* = proc(tmpl: XmlTemplate, value: dyn): dyn

    XmlAttrFilter* = ref object of Facet
        name*: string

    XmlEngine* = ref object of Class
        tmplCache: TableRef[string, XmlNode]
        elements: TableRef[string, ElementHook]
        attrfilters: TableRef[string, AttrFilterHook]

begin XmlNode:
    method delete*(child: XmlNode): void {. base .} =
        for i in 0..<this.len:
            if child == this[i]:
                this.delete(i)
                break

    method min(): XmlNode {. base .} =
        const
            txt = [xnText, xnVerbatimText]
            pre = ["pre", "code", "textarea", "script", "style"]
            inl = [
                "a", "abbr", "acronym", "audio", "b", "bdi", "bdo", "big", "br",
                "button", "canvas", "cite", "code", "data", "datalist", "del",
                "dfn", "em", "embed", "i", "iframe", "img", "input", "ins", "kbd",
                "label", "map", "mark", "meter", "object", "output",
                "picture", "progress", "q", "ruby", "s", "samp", "select",
                "slot", "small", "span", "strong", "sub", "sup", "svg", "template",
                "textarea", "time", "u", "tt", "var", "video", "wbr"
            ]

        result = this

        for i in 0..this.len - 1:
            if this[i].kind in txt:
                this[i].text = this[i].text.replace("\r\n", "\n").replace("\r", "\n")

        if this.kind == xnElement and this.tag.toLowerAscii notin pre:
            var
                i = -1
                l = this.len

            while i+1 < l:
                inc i

                let
                    name = this.tag.toLowerAscii()
                    next = if i+1 < l: this[i+1] else: nil
                    prev = if i-1 >= 0: this[i-1] else: nil

                if this[i].kind == xnElement:
                    discard this[i].min()
                elif this[i].kind in txt:
                    var
                        core = this[i].text.strip(chars = {' ', '\t', '\n'})
                    let
                        part = this[i].text.replace(core, ":").split(":")

                    if core.len > 0:
                        if name notin pre:
                            core = core.replace("\n", " ")
                            while true:
                                let
                                    size = core.len
                                core = core.replace("  ", " ")
                                if core.len == size:
                                    break

                        if part[0].len > 0:
                            core = " " & core
                        if part.len > 1 and part[1].len > 0:
                            core = core & " "
                    else:
                        core = " "

                    if prev == nil:
                        if name notin inl:
                            core = core.strip(trailing = false)
                    else:
                        if prev.kind == xnElement:
                            if prev.tag.toLowerAscii() notin inl:
                                core = core.strip(trailing = false)

                    if next == nil:
                        if name notin inl:
                            core = core.strip(leading = false)
                    else:
                        if next.kind == xnElement:
                            if next.tag.toLowerAscii() notin inl:
                                core = core.strip(leading = false)


                    if core != "":
                        this[i].text = core
                    else:
                        this.delete(i)
                        dec i
                        dec l

begin XmlEngine:
    proc init*(): void =
        this.tmplCache = newTable[string, XmlNode]()
        this.elements = newTable[string, ElementHook]()
        this.attrFilters = newTable[string, AttrFilterHook]()

    method filter*(tmpl: XmlTemplate, name: string, value: dyn): dyn {. base .} =
        if not this.attrFilters.hasKey(name):
            raise newException(ValueError, fmt "Unknown filter '{name}'")

        result = this.attrFilters[name](tmpl, value)

    method load(loader: proc(): XmlTemplate, hash: string, data: dyn = nil): XmlTemplate {. base .} =
        if this.tmplCache.contains(hash):
            when defined debug:
                echo fmt "Loading template [{hash}] from cache"

            result = XmlTemplate(
                engine: this,
                root: this.tmplCache[hash]
            )

            if data != nil:
                result.data.add(data)
        else:
            when defined debug:
                echo fmt "Storing template [{hash}] to cache"

            result = loader()
            this.tmplCache[hash] = result.root

    method loadString*(content: string, data: dyn = nil): XmlTemplate {. base .} =
        let
            loader = proc(): XmlTemplate =
                let
                    stream = newStringStream("<x>" & content.strip & "</x>")

                result = XmlTemplate(
                    engine: this,
                    root: parseXml(stream, {
                        allowEmptyAttribs,
                        allowUnquotedAttribs,
                        reportWhitespace
                    })
                )

                if data != nil:
                    result.data.add(data)

                close(stream)

        if this.useCache:
            result = this.load(loader, content.getMD5(), data)
        else:
            result = loader()


    method loadFile*(filename: string, data: dyn = nil): XmlTemplate {. base .} =
        let
            loader = proc(): XmlTemplate =
                let
                    stream = newFileStream(filename, fmRead)

                if stream == nil:
                    raise newException(ValueError, "Cannot load file")

                result = this.loadString(stream.readAll(), data)
                stream.close()

        if this.useCache:
            result = this.load(loader, filename.getMD5(), data)
        else:
            result = loader()

    method withElement*(name: string, hook: ElementHook): void {. base .} =
        this.elements[name] = hook

    method withAttrFilter*(name: string, hook: AttrFilterHook): void {. base .} =
        this.attrFilters[name] = hook

begin XmlTemplate:
    method scope(index: var int): dyn {. base .} =
        if index < 0:
            index = this.data.high + index

        if index < 0 or index > this.data.high:
            raise newException(ValueError, fmt "Failed reading scope @ index {$index}, not available")

        result = this.data[index]

    method context*(): dyn {. base .} =
        result = ()

        for i in 0..this.data.high:
            for name, value in this.data[i].pairs:
                result[name] = value

    method scope*(): dyn {. base .} =
        var
            current = this.data.high

        if current < 0:
            current = 0
            this.data.add(())

        result = this.scope(current)

    method closeScope*(): void {. base .} =
        discard this.data.pop()

    method beginScope*(scope: dyn = null) {. base .} =
        if scope == null:
            this.data.add(copy this.scope)
        else:
            this.data.add(scope)

    method closeMode*(): void {. base .} =
        discard this.mode.pop()

    method beginMode*(mode: XmlMode) {. base .} =
        this.mode.add(mode)

    method eval*(value: dyn): dyn {. base .} =
        if this.mode[^1] == XmlRaw:
            result = value
        else:
            result = Script.eval(value, this.scope)

    method fill*(value: string): string {. base .} =
        if this.mode[^1] == XmlRaw:
            result = value
        else:
            result = Script.fill(value, this.scope)

    method getAttrs*(node: XmlNode, ours: seq[string] = @[]): Table[string, dyn] {. base .} =
        if node.attrsLen > 0:
            for key, value in node.attrs.pairs:
                let
                    parts = key.split(':')

                if this.mode[^1] != XmlRaw and parts.len > 1 and (ours.len == 0 or parts[0] in ours):
                    if parts.len >= 2 and parts[^1] == "":
                        # Ignore merge attributes
                        discard
                    else:
                        let
                            key = parts[0]

                        result[key] = value

                        for i in 1..parts.high:
                            result[key] = this.engine.filter(this, parts[i], result[key])
                else:
                    result[key] = this.fill(value)


    method clone*(node: XmlNode): XmlNode {. base .} =
        result = newXmlTree(node.tag, [], toXmlAttributes())

        if node.attrs != nil:
            for name, value in node.attrs.pairs:
                result.attrs[name] = this.fill(value)

    method add*(head, node, parent: XmlNode, merge = newTable[string, string]()): void {. base .} =
        case node.kind:
            of xnElement:
                let
                    tag = node.tag

                if this.mode[^1] != XmlRaw and this.engine.elements.hasKey(tag):
                    when defined debug:
                        echo fmt "Performing custom handling for <{tag}>"
                    this.engine.elements[tag](this, head, node, parent)
                elif tag == "x" or tag.startsWith("x:"):
                    let
                        parts = tag.split(":")
                        path = parts[1..^1].join("/").strip(chars = {'/'}, leading = false)

                    if node.attrs != nil:
                        for name, value in node.attrs.pairs:
                            if name[^1] == ':':
                                merge[name.strip(chars = {':'}, leading = false)] = value

                    if path != "":
                        let
                            tmpl = this.engine.loadFile("resources/tags/" & path & ".html")

                        this.beginScope((context: this.context))

                        for name, value in this.getAttrs(node).pairs:
                            this.scope[name] = value

                        for child in tmpl.root:
                            this.add(head, child, parent, merge)

                        this.closeScope()
                    else:
                        for child in node:
                            this.add(head, child, parent, merge)
                else:
                    let
                        clone = this.clone(node)
                    for name, value in merge.pairs:
                        if clone.attrs.contains(name):
                            clone.attrs[name] = clone.attrs[name] & " " & this.fill(value)
                        else:
                            clone.attrs[name] = this.fill(value)
                    for child in node:
                        this.add(clone, child, node)
                    head.add(clone)

            of xnText, xnVerbatimText:
                if node.text.strip == "":
                    head.add(node)
                else:
                    case this.mode[^1]:
                        of XmlRaw:
                            head.add(node)
                        of XmlEsc:
                            head.add(newText(this.fill(node.text)))
                        of XmlSec:
                            head.add(newVerbatimText(this.fill(node.text)))
            else:
                discard

    method process*(data: dyn = nil, mode: XmlMode = XmlEsc): XmlNode {. base .} =
        this.mode.add(mode)

        if data != nil:
            this.data.add(data)

        for child in this.root:
            this.add(this.tree, child, child)

        result = this.tree

    method render*(data: dyn = nil, mode: XmlMode = XmlEsc): string {. base .} =
        for child in this.process(data, mode):
            when defined debug:
                result.add(child.min(), 0, 4, true)
            else:
                result.add(child.min(), 0, 0, false)

    #[

    ]#
    method set*(name: string, value: dyn): void {. base .} =
        this.scope[name] = value

    method put*(name: string, value: string): void {. base .} =
        this.scope[name] = Script.eval(value, this.scope)

shape XmlEngine: @[
    Shared(),
    Delegate(
        call: DelegateHook as (
            block:
                result = shape.init()

                for element in this.app.config.findAll(XmlElement):
                    result.withElement(element.name, element[ElementHook])

                for filter in this.app.config.findAll(XmlAttrFilter):
                    result.withAttrFilter(filter.name, filter[AttrFilterHook])

        )
    ),
    XmlAttrFilter(
        name: "val",
        call: AttrFilterHook as (
            block:
                result = tmpl.eval(value)
        )
    ),
    XmlAttrFilter(
        name: "raw",
        call: AttrFilterHook as (
            block:
                result = value
        )
    ),
    XmlElement(
        name: "script",
        call: ElementHook as (
            block:
                tmpl.beginMode(XmlSec)

                let
                    script = tmpl.clone(node)

                if node.len == 0:
                    tmpl.add(script, newText(""), parent)
                else:
                    for child in node:
                        tmpl.add(script, child, parent)

                tmpl.closeMode()
                head.add(script)
        )
    ),
    XmlElement(
        name: "raw",
        call: ElementHook as (
            block:
                for child in node:
                    let
                        plate = tmpl.engine.loadString(tmpl.fill($child))
                        tree = plate.process((), XmlRaw)

                    for subchild in tree:
                        head.add(subchild)
        )
    ),
    XmlElement(
        name: "mix",
        call: ElementHook as (
            block:
                for child in node:
                    let
                        plate = tmpl.engine.loadString(tmpl.fill($child))
                        tree = plate.process(copy tmpl.scope)

                    for subchild in tree:
                        head.add(subchild)
        )
    ),
    XmlElement(
        name: "set",
        call: ElementHook as (
            block:
                for key, value in tmpl.getAttrs(node):
                    tmpl.set(key, value)
        )
    ),
    XmlElement(
        name: "val",
        call: ElementHook as (
            block:
                let
                    attrs  = tmpl.getAttrs(node, @["name"])
                if not attrs.hasKey("name"):
                    raise newException(ValueError, "The `val` tag must provide a `name` attribute")

                tmpl.put(attrs["name"], node.innerText)
        )
    ),
    XmlElement(
        name: "do",
        call: ElementHook as (
            block:
                let
                    attrs  = tmpl.getAttrs(node, @["if"])
                if not attrs.hasKey("if"):
                    raise newException(ValueError, "The `do` tag outside a `try` must provide an `if` attribute")
                if attrs["if"]:
                    for child in node:
                        tmpl.add(head, child, parent)
        )
    ),
    XmlElement(
        name: "try",
        call: ElementHook as (
            block:
                for child in node:
                    if child.kind == xnElement and child.tag != "do":
                        raise newException(ValueError, "The `try` tag must contain only `do` tags")

                for child in node:
                    if child.kind == xnElement:
                        let
                            attrs = tmpl.getAttrs(child, @["if"])
                        if not attrs.hasKey("if") or attrs["if"]:
                            for dochild in child:
                                tmpl.add(head, dochild, parent)
                            break
        )

    ),
    XmlElement(
        name: "for",
        call: ElementHook as (
            block:
                let
                    attrs  = tmpl.getAttrs(node, @["key", "val", "in"])
                    valSet = attrs.hasKey("val")
                    keySet = attrs.hasKey("key")

                if not attrs.hasKey("in"):
                    raise newException(ValueError, "The `for` tag must provide an `in` attribute")

                if attrs["in"] of array:
                    tmpl.beginScope()
                    for i in 0..^attrs["in"]:
                        if valSet:
                            tmpl.set(attrs["val"], attrs["in"][i])
                        if keySet:
                            tmpl.set(attrs["key"], i)
                        for child in node:
                            tmpl.add(head, child, parent)

                    tmpl.closeScope()

                elif attrs["in"] of object:
                    discard
                else:
                    raise newException(ValueError, "The 'in' attribute must be array/object")
        )
    ),
]

converter toResponse*(tmpl: XmlTemplate): Response =
    result = Response(
        status: HttpCode(200),
        stream: newStringStream(tmpl.render()),
        headers: HttpHeaders(@[
            ("Content-Type", "text/html; ustf-8")
        ])
    )

begin Action:
    method xmlengine: XmlEngine {. base .} =
        result = this.app.get(XmlEngine)

    method html*(file: string, data: dyn = ()): XmlTemplate {. base .} =
        result = this.xmlengine.loadFile(file, data)
