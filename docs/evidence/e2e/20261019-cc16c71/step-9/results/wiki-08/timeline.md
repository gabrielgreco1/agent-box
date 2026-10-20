# Timeline: wiki-08

```
02:00:40.801  HTTP    ERR GET egress direct http://clients2.google.com/time/1/current?cup2key=[redacted]&cup2hreq=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 error=blocked: noise BLOCKED=noise
02:00:40.818  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
02:00:40.829  HTTP    ERR CONNECT egress direct update.googleapis.com:443 error=blocked: noise BLOCKED=noise
02:00:41.785  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
02:00:42.634  PLAN    Open en.wikipedia.org/wiki/Portugal on wiki-08, read title and first non-empty paragraph, submit result with request-id citations.
02:00:42.905  DOING   browser_open https://en.wikipedia.org/wiki/Portugal
02:00:43.310  HTTP    200 GET browser direct https://en.wikipedia.org/w/load.php?lang=en&modules=startup&only=scripts&raw=1&skin=vector-2022
02:00:43.351  HTTP    ERR CONNECT egress direct content-autofill.googleapis.com:443 error=blocked: noise BLOCKED=noise
02:00:43.352  HTTP    ERR CONNECT egress direct content-autofill.googleapis.com:443 error=blocked: noise BLOCKED=noise
02:00:43.652  HTTP    200 GET browser direct https://en.wikipedia.org/wiki/Portugal
02:00:43.655  HTTP    200 GET browser direct https://en.wikipedia.org/w/load.php?lang=en&modules=ext.gadget.ReferenceTooltips%2CWikiMiniAtlas%2Cswitcher&skin=vector-2022&version=1r5wh
02:00:43.658  HTTP    200 GET browser direct https://en.wikipedia.org/w/load.php?lang=en&modules=ext.visualEditor.core.utils.parsing%7Cext.visualEditor.desktopArticleTarget.init%7Cext.visualEditor.progressBarWidget%2CsupportC
02:00:43.659  HTTP    302 GET browser direct https://en.wikipedia.org/wiki/Special:CentralAutoLogin/start?useformat=desktop&type=script&usesul3=1
02:00:43.731  HTTP    200 GET browser direct https://en.wikipedia.org/w/load.php?lang=en&modules=ext.centralNotice.bannerHistoryLogger%2CchoiceData%2Cdisplay%2CgeoIP%2CimpressionDiet%2CkvStore%2ClegacySupport%2CstartUp%7Cext.
02:00:43.733  HTTP    200 GET browser direct https://en.wikipedia.org/w/load.php?lang=en&modules=mw.config.values.wbCurrentSiteDetails%2CwbRepo%7Coojs-ui.styles.icons-editing-core&skin=vector-2022&version=1egjk
02:00:43.734  HTTP    202 POST browser direct https://en.wikipedia.org/ins-502b/v2/events?hasty=true
02:00:43.734  HTTP    200 GET browser direct https://auth.wikimedia.org/metawiki/wiki/Special:CentralAutoLogin/checkLoggedIn?useformat=desktop&wikiid=enwiki&usesul3=1&type=script
02:00:43.738  HTTP    200 GET browser direct https://en.wikipedia.org/w/load.php?lang=en&modules=ext.cite.referencePreviews%7Cext.math.popup%7Cext.popups.main&skin=vector-2022&version=zzdks
02:00:43.819  HTTP    200 GET browser direct https://en.wikipedia.org/static/favicon/wikipedia.ico
02:00:44.340  HTTP    ERR CONNECT egress direct content-autofill.googleapis.com:443 error=blocked: noise BLOCKED=noise
02:00:44.721  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
02:00:45.092  HTTP    ERR CONNECT egress direct content-autofill.googleapis.com:443 error=blocked: noise BLOCKED=noise
02:00:47.279  HTTP    ERR CONNECT egress direct content-autofill.googleapis.com:443 error=blocked: noise BLOCKED=noise
02:00:50.838  HTTP    ERR CONNECT egress direct www.google.com:443
02:00:51.036  HTTP    ERR CONNECT egress direct content-autofill.googleapis.com:443 error=blocked: noise BLOCKED=noise
02:00:53.244  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
02:00:53.412  FOUND   Page loaded (status 200, title "Portugal - Wikipedia"). Heading "Portugal". First non-empty paragraph in #mw-content-text (first of 95 p elements) starts "Portugal,[c] officially the Portuguese Republic..." Citations are the page-load request id.  [evidence: 01M5BGM7B352XXY0EC2Q6JZ5QA]
02:00:54.407  NOTE    result submitted: 2 verified, 0 cited_missing, 1 not_verified
```
