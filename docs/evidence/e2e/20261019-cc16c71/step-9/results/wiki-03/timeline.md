# Timeline: wiki-03

```
02:00:14.884  HTTP    ERR GET egress direct http://clients2.google.com/time/1/current?cup2key=[redacted]&cup2hreq=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 error=blocked: noise BLOCKED=noise
02:00:14.989  HTTP    ERR CONNECT egress direct update.googleapis.com:443 error=blocked: noise BLOCKED=noise
02:00:15.022  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
02:00:16.017  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
02:00:18.741  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
02:00:21.501  PLAN    Open en.wikipedia.org/wiki/Japan on wiki-03, read title and first non-empty paragraph, submit result.json with request-id citations, release box.
02:00:21.948  HTTP    ERR CONNECT egress direct content-autofill.googleapis.com:443 error=blocked: noise BLOCKED=noise
02:00:21.949  HTTP    ERR CONNECT egress direct content-autofill.googleapis.com:443 error=blocked: noise BLOCKED=noise
02:00:22.233  HTTP    200 GET browser direct https://en.wikipedia.org/wiki/Japan
02:00:22.236  HTTP    200 GET browser direct https://en.wikipedia.org/w/load.php?lang=en&modules=startup&only=scripts&raw=1&skin=vector-2022
02:00:22.237  HTTP    302 GET browser direct https://en.wikipedia.org/wiki/Special:CentralAutoLogin/start?useformat=desktop&type=script&usesul3=1
02:00:22.238  HTTP    200 GET browser direct https://en.wikipedia.org/w/load.php?lang=en&modules=ext.gadget.ReferenceTooltips%2CWikiMiniAtlas%2Cswitcher&skin=vector-2022&version=1r5wh
02:00:22.241  HTTP    200 GET browser direct https://en.wikipedia.org/w/load.php?lang=en&modules=ext.visualEditor.core.utils.parsing%7Cext.visualEditor.desktopArticleTarget.init%7Cext.visualEditor.progressBarWidget%2CsupportC
02:00:22.331  HTTP    200 GET browser direct https://en.wikipedia.org/w/load.php?lang=en&modules=ext.centralNotice.bannerHistoryLogger%2CchoiceData%2Cdisplay%2CgeoIP%2CimpressionDiet%2CkvStore%2ClegacySupport%2CstartUp%7Cext.
02:00:22.332  HTTP    200 GET browser direct https://en.wikipedia.org/w/load.php?lang=en&modules=mw.config.values.wbCurrentSiteDetails%2CwbRepo%7Coojs-ui.styles.icons-editing-core&skin=vector-2022&version=1egjk
02:00:22.337  HTTP    200 GET browser direct https://en.wikipedia.org/w/load.php?lang=en&modules=ext.cite.referencePreviews%7Cext.math.popup%7Cext.popups.main&skin=vector-2022&version=zzdks
02:00:22.338  HTTP    202 POST browser direct https://en.wikipedia.org/ins-502b/v2/events?hasty=true
02:00:22.343  HTTP    200 GET browser direct https://en.wikipedia.org/static/favicon/wikipedia.ico
02:00:22.368  HTTP    200 GET browser direct https://auth.wikimedia.org/metawiki/wiki/Special:CentralAutoLogin/checkLoggedIn?useformat=desktop&wikiid=enwiki&usesul3=1&type=script
02:00:22.777  HTTP    ERR CONNECT egress direct content-autofill.googleapis.com:443 error=blocked: noise BLOCKED=noise
02:00:23.503  HTTP    ERR CONNECT egress direct content-autofill.googleapis.com:443 error=blocked: noise BLOCKED=noise
02:00:25.048  HTTP    ERR CONNECT egress direct www.google.com:443
02:00:26.476  HTTP    ERR CONNECT egress direct content-autofill.googleapis.com:443 error=blocked: noise BLOCKED=noise
02:00:26.850  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
02:00:30.470  HTTP    ERR CONNECT egress direct content-autofill.googleapis.com:443 error=blocked: noise BLOCKED=noise
02:00:33.570  NOTE    result submitted: 2 verified, 0 cited_missing, 1 not_verified
```
