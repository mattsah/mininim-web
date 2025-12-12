import
    mininim,
    mininim/web,
    mininim/templates

type
    StatusPages = ref object of Class

begin StatusPages:
    method handle(request: Request, next: MiddlewareNext): Response =
        result = next(request)

        if result.status.int <= 300:
            return result

        var
            tryTemplate = ""
        let
            status = result.status.int

        when defined debug:
            if status == 301:
                tryTemplate = $status

        if status >= 400 and status < 500:
            tryTemplate = $status

        if tryTemplate.len != "":
            tryTemplate = "resources/pages/" & tryTemplate & ".html"

            if os.fileExists(tryTemplate):
                let
                    tmpl = this.app.get(TemplateEngine).loadFile(tryTemplate, ())
                tmpl.setGlobal((
                    request: request
                ))
                result = tmpl

shape StatusPages: @[
    Middleware(
        name: "statuspages",
        priority: 800
    )
]
