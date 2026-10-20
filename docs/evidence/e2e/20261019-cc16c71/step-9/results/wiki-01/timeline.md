# Timeline: wiki-01

```
02:00:14.902  HTTP    ERR GET egress direct http://clients2.google.com/time/1/current?cup2key=[redacted]&cup2hreq=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 error=blocked: noise BLOCKED=noise
02:00:14.981  HTTP    ERR CONNECT egress direct update.googleapis.com:443 error=blocked: noise BLOCKED=noise
02:00:15.016  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
02:00:15.986  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
02:00:18.601  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
02:00:20.300  PLAN    Open https://en.wikipedia.org/wiki/Chile on wiki-01 via browser, read title and first non-empty paragraph, submit result.json with request-id citations, then release the box.
02:00:20.489  DOING   browser_open https://en.wikipedia.org/wiki/Chile
02:00:20.918  HTTP    ERR CONNECT egress direct content-autofill.googleapis.com:443 error=blocked: noise BLOCKED=noise
02:00:20.920  HTTP    ERR CONNECT egress direct content-autofill.googleapis.com:443 error=blocked: noise BLOCKED=noise
02:00:21.203  HTTP    200 GET browser direct https://en.wikipedia.org/wiki/Chile
02:00:21.207  HTTP    200 GET browser direct https://en.wikipedia.org/w/load.php?lang=en&modules=startup&only=scripts&raw=1&skin=vector-2022
02:00:21.207  HTTP    302 GET browser direct https://en.wikipedia.org/wiki/Special:CentralAutoLogin/start?useformat=desktop&type=script&usesul3=1
02:00:21.210  HTTP    200 GET browser direct https://en.wikipedia.org/w/load.php?lang=en&modules=ext.gadget.ReferenceTooltips%2CWikiMiniAtlas%2Cswitcher&skin=vector-2022&version=1r5wh
02:00:21.214  HTTP    200 GET browser direct https://en.wikipedia.org/w/load.php?lang=en&modules=ext.visualEditor.core.utils.parsing%7Cext.visualEditor.desktopArticleTarget.init%7Cext.visualEditor.progressBarWidget%2CsupportC
02:00:21.289  HTTP    200 GET browser direct https://en.wikipedia.org/w/load.php?lang=en&modules=mw.config.values.wbCurrentSiteDetails%2CwbRepo%7Coojs-ui.styles.icons-editing-core&skin=vector-2022&version=1egjk
02:00:21.318  HTTP    200 GET browser direct https://en.wikipedia.org/w/load.php?lang=en&modules=ext.centralNotice.bannerHistoryLogger%2CchoiceData%2Cdisplay%2CgeoIP%2CimpressionDiet%2CkvStore%2ClegacySupport%2CstartUp%7Cext.
02:00:21.323  HTTP    200 GET browser direct https://en.wikipedia.org/w/load.php?lang=en&modules=ext.cite.referencePreviews%7Cext.math.popup%7Cext.popups.main&skin=vector-2022&version=zzdks
02:00:21.324  HTTP    202 POST browser direct https://en.wikipedia.org/ins-502b/v2/events?hasty=true
02:00:21.324  HTTP    200 GET browser direct https://en.wikipedia.org/static/favicon/wikipedia.ico
02:00:21.365  HTTP    200 GET browser direct https://auth.wikimedia.org/metawiki/wiki/Special:CentralAutoLogin/checkLoggedIn?useformat=desktop&wikiid=enwiki&usesul3=1&type=script
02:00:21.850  HTTP    ERR CONNECT egress direct content-autofill.googleapis.com:443 error=blocked: noise BLOCKED=noise
02:00:22.322  HTTP    ERR CONNECT egress direct content-autofill.googleapis.com:443 error=blocked: noise BLOCKED=noise
02:00:25.010  HTTP    ERR CONNECT egress direct www.google.com:443
02:00:25.487  HTTP    ERR CONNECT egress direct content-autofill.googleapis.com:443 error=blocked: noise BLOCKED=noise
02:00:26.205  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
02:00:28.869  HTTP    ERR CONNECT egress direct content-autofill.googleapis.com:443 error=blocked: noise BLOCKED=noise
02:00:37.736  HTTP    ERR CONNECT egress direct content-autofill.googleapis.com:443 error=blocked: noise BLOCKED=noise
02:00:38.697  NOTE    result submitted: 2 verified, 0 cited_missing, 1 not_verified
```
