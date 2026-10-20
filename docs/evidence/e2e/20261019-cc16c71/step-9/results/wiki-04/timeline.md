# Timeline: wiki-04

```
02:00:14.927  HTTP    ERR GET egress direct http://clients2.google.com/time/1/current?cup2key=[redacted]&cup2hreq=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 error=blocked: noise BLOCKED=noise
02:00:15.004  HTTP    ERR CONNECT egress direct update.googleapis.com:443 error=blocked: noise BLOCKED=noise
02:00:15.029  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
02:00:15.857  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
02:00:18.857  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
02:00:22.691  PLAN    Open https://en.wikipedia.org/wiki/Kenya on wiki-04, read title and first non-empty paragraph, submit result.json with request-id citations, release box.
02:00:23.197  HTTP    ERR CONNECT egress direct content-autofill.googleapis.com:443 error=blocked: noise BLOCKED=noise
02:00:23.198  HTTP    ERR CONNECT egress direct content-autofill.googleapis.com:443 error=blocked: noise BLOCKED=noise
02:00:23.283  HTTP    200 GET browser direct https://en.wikipedia.org/w/load.php?lang=en&modules=startup&only=scripts&raw=1&skin=vector-2022
02:00:23.320  HTTP    200 GET browser direct https://en.wikipedia.org/wiki/Kenya
02:00:23.321  HTTP    302 GET browser direct https://en.wikipedia.org/wiki/Special:CentralAutoLogin/start?useformat=desktop&type=script&usesul3=1
02:00:23.332  HTTP    200 GET browser direct https://en.wikipedia.org/w/load.php?lang=en&modules=ext.gadget.ReferenceTooltips%2CWikiMiniAtlas%2Cswitcher&skin=vector-2022&version=1r5wh
02:00:23.335  HTTP    200 GET browser direct https://en.wikipedia.org/w/load.php?lang=en&modules=ext.visualEditor.core.utils.parsing%7Cext.visualEditor.desktopArticleTarget.init%7Cext.visualEditor.progressBarWidget%2CsupportC
02:00:23.432  HTTP    200 GET browser direct https://en.wikipedia.org/w/load.php?lang=en&modules=ext.centralNotice.bannerHistoryLogger%2CchoiceData%2Cdisplay%2CgeoIP%2CimpressionDiet%2CkvStore%2ClegacySupport%2CstartUp%7Cext.
02:00:23.433  HTTP    200 GET browser direct https://en.wikipedia.org/w/load.php?lang=en&modules=mw.config.values.wbCurrentSiteDetails%2CwbRepo%7Coojs-ui.styles.icons-editing-core&skin=vector-2022&version=1egjk
02:00:23.434  HTTP    200 GET browser direct https://en.wikipedia.org/static/favicon/wikipedia.ico
02:00:23.434  HTTP    202 POST browser direct https://en.wikipedia.org/ins-502b/v2/events?hasty=true
02:00:23.435  HTTP    200 GET browser direct https://auth.wikimedia.org/metawiki/wiki/Special:CentralAutoLogin/checkLoggedIn?useformat=desktop&wikiid=enwiki&usesul3=1&type=script
02:00:23.439  HTTP    200 GET browser direct https://en.wikipedia.org/w/load.php?lang=en&modules=ext.cite.referencePreviews%7Cext.math.popup%7Cext.popups.main&skin=vector-2022&version=zzdks
02:00:24.135  HTTP    ERR CONNECT egress direct content-autofill.googleapis.com:443 error=blocked: noise BLOCKED=noise
02:00:24.998  HTTP    ERR CONNECT egress direct content-autofill.googleapis.com:443 error=blocked: noise BLOCKED=noise
02:00:25.057  HTTP    ERR CONNECT egress direct www.google.com:443
02:00:27.207  HTTP    ERR CONNECT egress direct content-autofill.googleapis.com:443 error=blocked: noise BLOCKED=noise
02:00:27.657  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
02:00:31.356  HTTP    ERR CONNECT egress direct content-autofill.googleapis.com:443 error=blocked: noise BLOCKED=noise
02:00:34.220  FOUND   Kenya Wikipedia article loaded (status 200). Heading "Kenya"; first non-empty paragraph in #mw-content-text read via browser_eval. Evidence: page load request 01M5BGKKMM00Y3TB1VKM5ZHJH6.  [evidence: 01M5BGKKMM00Y3TB1VKM5ZHJH6]
02:00:35.690  NOTE    result submitted: 2 verified, 0 cited_missing, 1 not_verified
```
