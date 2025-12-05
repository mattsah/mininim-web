import
    mininim,
    mininim/dic,
    mininim/script,
    mininim/web/router,
    checksums/md5,
    std/htmlparser,
    std/xmltree,
    std/streams,
    std/strtabs

export
    xmltree

type
    TemplateMode* = enum
        XmlRaw
        XmlEsc

    Template* = ref object of Class
        root: XmlNode
        mode: seq[TemplateMode]
        data: seq[dyn] = @[]
        tree: XmlNode = newXmlTree("x", [])
        engine*: TemplateEngine

    ElementHook* = proc(tmpl: Template, head: XmlNode, node: XmlNode, parent: XmlNode): void

    Element* = ref object of Facet
        name*: string

    AttrFilterHook* = proc(tmpl: Template, value: dyn): dyn

    AttrFilter* = ref object of Facet
        name*: string

    TemplateEngine* = ref object of Class
        tmplCache: TableRef[string, XmlNode]
        elements: TableRef[string, ElementHook]
        attrfilters: TableRef[string, AttrFilterHook]

begin XmlNode:
    converter asDyn(): dyn =
        case this.kind:
            of xnElement:
                result = (
                    kind: "element",
                    name: this.tag,
                    children: this.mapIt(asDyn(it)),
                    attrs: ~()
                )

                if this.attrsLen > 0:
                    for name, value in this.attrs:
                        result.attrs[name] = value
            else:
                result = (
                    kind: case this.kind:
                        of xnText, xnVerbatimText: "text"
                        of xnEntity: "entity"
                        else: "unknown",
                    text: this.text
                )

        result.toString = dynToString as (
            block:
                if this.kind == "element":
                    result = "<" & this.name
                    if this.attrs.len > 0:
                        for name, value in this.attrs:
                            result = result & " " & name & "=\"" & value & "\""
                    if this.children.len == 0:
                        result = result & " />"
                    else:
                        result = result & ">"
                        for child in this.children:
                            result = result & child
                        result = result & "</" & this.name & ">"
                elif this.kind == "entity":
                    result = "&" & this.text & ";"
                else:
                    result = this.text
        )

    method escape*(): string {. base .} =
        result = xmltree.escape($this)

    method delete*(child: XmlNode): void {. base .} =
        for i in 0..<this.len:
            if child == this[i]:
                this.delete(i)
                break

    method fix(): void {. base .} =
        const
            badEntities = @[
                ("<", "lt"),
                (">", "gt"),
                ("'", "apos"),
                ("\"", "quot")
            ].toTable()

        var
            i = -1
            l = this.len

        while i + 1 < l:
            inc i
            case this[i].kind:
                of xnElement:
                    this[i].fix()
                of xnText:
                    if this.tag == "script":
                        continue

                    if this[i].text.len == 1:
                        if badEntities.hasKey(this[i].text):
                            this.replace(i, [newEntity(badEntities[this[i].text])])
                            continue

                    if i > 0:
                        if this[i-1].kind == xnText:
                            this[i].text = this[i-1].text & this[i].text
                            this.delete(i-1)
                            dec i
                            dec l
                            continue
                else:
                    discard

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

begin TemplateEngine:
    proc init*(): void =
        this.tmplCache = newTable[string, XmlNode]()
        this.elements = newTable[string, ElementHook]()
        this.attrFilters = newTable[string, AttrFilterHook]()

    method filter*(tmpl: Template, name: string, value: dyn): dyn {. base .} =
        if not this.attrFilters.hasKey(name):
            raise newException(ValueError, fmt "Unknown filter '{name}'")

        result = this.attrFilters[name](tmpl, value)

    method load(loader: proc(): Template, hash: string, data: dyn = nil): Template {. base .} =
        if this.tmplCache.contains(hash):
            when defined debug:
                echo fmt "Loading template [{hash}] from cache"

            result = Template(
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

    method loadString*(content: string, data: dyn = nil): Template {. base .} =
        let
            loader = proc(): Template =
                let
                    stream = newStringStream("<x>" & content.strip & "</x>")

                result = Template(
                    engine: this,
                    root: parseHtml(stream)
                )

                result.root.fix()

                if data != nil:
                    result.data.add(data)

                close(stream)

        if this.useCache:
            result = this.load(loader, content.getMD5(), data)
        else:
            result = loader()


    method loadFile*(filename: string, data: dyn = nil): Template {. base .} =
        let
            loader = proc(): Template =
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

begin Template:
    method context*(): dyn {. base .} =
        result = ()

        for i in 0..this.data.high:
            for name, value in this.data[i]:
                result[name] = value

    method scope(index: var int): dyn {. base .} =
        if index < 0:
            index = this.data.high + index

        if index < 0 or index > this.data.high:
            raise newException(ValueError, fmt "Failed reading scope @ index {$index}, not available")

        result = this.data[index]

    method scope*(): dyn {. base .} =
        var
            current = this.data.high

        if current < 0:
            current = 0
            this.data.add(())

        result = this.scope(current)

    method beginScope*(scope: dyn = null) {. base .} =
        if scope == null:
            this.data.add(copy this.scope)
        else:
            this.data.add(scope)

    method closeScope*(): void {. base .} =
        discard this.data.pop()

    method beginMode*(mode: TemplateMode) {. base .} =
        this.mode.add(mode)

    method closeMode*(): void {. base .} =
        discard this.mode.pop()

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

    method clone*(node: XmlNode, deep: bool = false): XmlNode {. base .} =
        case node.kind:
            of xnElement:
                result = newXmlTree(node.tag, [], toXmlAttributes())

                if node.attrs != nil:
                    for name, value in node.attrs:
                        result.attrs[name] = this.fill(value)

                if deep:
                    for child in node:
                        result.add(this.clone(child, true))
            of xnText:
                result = newText(this.fill(node.text))
            else:
                result = deepcopy node

    method attrs*(node: XmlNode, ours: seq[string] = @[]): Table[string, dyn] {. base .} =
        if node.attrsLen > 0:
            for name, value in node.attrs:
                let
                    parts = name.split(':')

                if this.mode[^1] != XmlRaw and parts.len > 1 and (ours.len == 0 or parts[0] in ours):
                    if parts.len >= 2 and parts[^1] == "":
                        # Ignore merge attributes
                        discard
                    else:
                        let
                            name = parts[0]

                        result[name] = value

                        for i in 1..parts.high:
                            result[name] = this.engine.filter(this, parts[i], result[name])
                else:
                    result[name] = this.fill(value)

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
                        for name, value in node.attrs:
                            if name[^1] == ':':
                                let
                                    baseName = name.strip(chars = {':'}, leading = false)
                                if merge.contains(baseName):
                                    merge[baseName] = merge[baseName] & " " & value
                                else:
                                    merge[baseName] = value

                    if path != "":
                        var
                            children = ~[]
                            scope = ~()
                        let
                            tmpl = this.engine.loadFile("resources/tags/" & path & ".html")

                        for child in node:
                            if child.kind in [xnText, xnVerbatimText] and child.text.strip() == "":
                                continue
                            else:
                                children << child

                        for name, value in this.attrs(node):
                            scope[name] = value

                        scope.context = this.context
                        scope.children = children

                        this.beginScope(scope)

                        for child in tmpl.root:
                            this.add(head, child, parent, merge)

                        this.closeScope()
                    else:
                        for child in node:
                            this.add(head, child, parent, merge)
                else:
                    let
                        clone = this.clone(node)

                    for name, value in merge:
                        if clone.attrs.contains(name):
                            clone.attrs[name] = clone.attrs[name] & " " & this.fill(value)
                        else:
                            clone.attrs[name] = this.fill(value)

                    for child in node:
                        this.add(clone, child, node)

                    head.add(clone)

            else:
                head.add(this.clone(node))

    method process*(data: dyn = nil, mode: TemplateMode = XmlEsc): XmlNode {. base .} =
        this.mode.add(mode)

        if data != nil:
            this.data.add(data)

        for child in this.root:
            this.add(this.tree, child, child)

        result = this.tree

    method render*(data: dyn = nil, mode: TemplateMode = XmlEsc): string {. base .} =
        for child in this.process(data, mode):
            when defined debug:
                result.add(child.min(), 0, 4, true)
            else:
                result.add(child.min(), 0, 0, false)

    method set*(name: string, value: dyn): void {. base .} =
        this.scope[name] = value

    method put*(name: string, value: string): void {. base .} =
        this.scope[name] = Script.eval(value, this.scope)

shape TemplateEngine: @[
    Shared(),
    Delegate(
        call: DelegateHook as (
            block:
                result = shape.init()

                for element in this.app.config.findAll(Element):
                    result.withElement(element.name, element[ElementHook])

                for filter in this.app.config.findAll(AttrFilter):
                    result.withAttrFilter(filter.name, filter[AttrFilterHook])

        )
    ),
    AttrFilter(
        name: "val",
        call: AttrFilterHook as (
            block:
                result = tmpl.eval(value)
        )
    ),
    AttrFilter(
        name: "raw",
        call: AttrFilterHook as (
            block:
                result = value
        )
    ),
    Element(
        name: "script",
        call: ElementHook as (
            block:
                let
                    script = tmpl.clone(node)

                if node.len == 0:
                    tmpl.add(script, newVerbatimText(""), parent)
                else:
                    let
                        content = newVerbatimText("")

                    for child in node:
                        case child.kind:
                            of xnElement:
                                # If the child is an element, we move to raw mode and treat its rendered
                                # content as a verbatim string.  Note, raw mode prevents rendering {{ }} in
                                # the deep clone -- it is assumed HTML inside a script is being rendered
                                # independently if required
                                tmpl.beginMode(XmlRaw)
                                content.text = content.text & $(~child)
                                tmpl.closeMode()
                            else:
                                # If the child is anything else, we convert its text to a verbatim string
                                # but we do not use raw mode to enable rendering of {{ }}. and having values
                                # to be inject in scripts.  Note, that this implies XSS is always possible
                                # in the context of a <script> tag.
                                content.text = content.text & tmpl.fill($(~child))

                    script.add(content)

                head.add(script)
        )
    ),
    Element(
        name: "esc",
        call: ElementHook as(
            block:
                for child in node:
                    tmpl.beginMode(XmlRaw)
                    head.add(newText($tmpl.clone(child, true)))
                    tmpl.closeMode()
        )
    ),
    Element(
        name: "raw",
        call: ElementHook as (
            block:
                for child in node:
                    let
                        plate = tmpl.engine.loadString(tmpl.fill($(~child)))
                        tree = plate.process((), XmlRaw)

                    for subchild in tree:
                        head.add(subchild)
        )
    ),
    Element(
        name: "mix",
        call: ElementHook as (
            block:
                for child in node:
                    let
                        plate = tmpl.engine.loadString(tmpl.fill($(~child)))
                        tree = plate.process(copy tmpl.scope)

                    for subchild in tree:
                        head.add(subchild)
        )
    ),
    Element(
        name: "set",
        call: ElementHook as (
            block:
                for key, value in tmpl.attrs(node):
                    tmpl.set(key, value)
        )
    ),
    Element(
        name: "val",
        call: ElementHook as (
            block:
                let
                    attrs  = tmpl.attrs(node, @["name"])
                if not attrs.hasKey("name"):
                    raise newException(ValueError, "The `val` tag must provide a `name` attribute")

                tmpl.put(attrs["name"], node.innerText)
        )
    ),
    Element(
        name: "do",
        call: ElementHook as (
            block:
                let
                    attrs  = tmpl.attrs(node, @["if"])
                if not attrs.hasKey("if"):
                    raise newException(ValueError, "The `do` tag outside a `try` must provide an `if` attribute")
                if attrs["if"]:
                    for child in node:
                        tmpl.add(head, child, parent)
        )
    ),
    Element(
        name: "try",
        call: ElementHook as (
            block:
                for child in node:
                    if child.kind == xnElement and child.tag != "do":
                        raise newException(ValueError, "The `try` tag must contain only `do` tags")

                for child in node:
                    if child.kind == xnElement:
                        let
                            attrs = tmpl.attrs(child, @["if"])
                        if not attrs.hasKey("if") or attrs["if"]:
                            for dochild in child:
                                tmpl.add(head, dochild, parent)
                            break
        )

    ),
    Element(
        name: "for",
        call: ElementHook as (
            block:
                let
                    attrs  = tmpl.attrs(node, @["key", "val", "in"])
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

converter toResponse*(tmpl: Template): Response =
    result = Response(
        status: HttpCode(200),
        stream: newStringStream("<!doctype html>\n" & tmpl.render()),
        headers: HttpHeaders(@[
            ("Content-Type", "text/html; ustf-8")
        ])
    )

begin Action:
    method templates: TemplateEngine {. base .} =
        result = this.app.get(TemplateEngine)

    method html*(file: string, data: dyn = ()): Template {. base .} =
        result = this.templates.loadFile(file, data)
