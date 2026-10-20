# Timeline: wiki-10

```
02:00:52.951  HTTP    ERR GET egress direct http://clients2.google.com/time/1/current?cup2key=[redacted]&cup2hreq=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 error=blocked: noise BLOCKED=noise
02:00:52.966  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
02:00:52.986  HTTP    ERR CONNECT egress direct update.googleapis.com:443 error=blocked: noise BLOCKED=noise
02:00:53.944  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
02:00:54.986  PLAN    Open en.wikipedia.org/wiki/New_Zealand on wiki-10, read title and first non-empty article paragraph, submit result.json with request-id citations, release box.
02:00:55.195  HTTP    ERR CONNECT egress direct en.wikipedia.org:443
02:00:55.356  HTTP    ERR CONNECT egress direct content-autofill.googleapis.com:443 error=blocked: noise BLOCKED=noise
02:00:55.358  HTTP    ERR CONNECT egress direct content-autofill.googleapis.com:443 error=blocked: noise BLOCKED=noise
02:00:55.369  HTTP    200 GET browser direct https://en.wikipedia.org/w/load.php?lang=en&modules=startup&only=scripts&raw=1&skin=vector-2022
02:00:55.614  HTTP    200 GET browser direct https://en.wikipedia.org/wiki/New_Zealand
02:00:55.615  HTTP    302 GET browser direct https://en.wikipedia.org/wiki/Special:CentralAutoLogin/start?useformat=desktop&type=script&usesul3=1
02:00:55.617  HTTP    200 GET browser direct https://en.wikipedia.org/w/load.php?lang=en&modules=ext.gadget.ReferenceTooltips%2CWikiMiniAtlas%2Cswitcher&skin=vector-2022&version=1r5wh
02:00:55.620  HTTP    200 GET browser direct https://en.wikipedia.org/w/load.php?lang=en&modules=ext.visualEditor.core.utils.parsing%7Cext.visualEditor.desktopArticleTarget.init%7Cext.visualEditor.progressBarWidget%2CsupportC
02:00:55.703  HTTP    200 GET browser direct https://en.wikipedia.org/w/load.php?lang=en&modules=ext.centralNotice.bannerHistoryLogger%2CchoiceData%2Cdisplay%2CgeoIP%2CimpressionDiet%2CkvStore%2ClegacySupport%2CstartUp%7Cext.
02:00:55.705  HTTP    200 GET browser direct https://en.wikipedia.org/w/load.php?lang=en&modules=mw.config.values.wbCurrentSiteDetails%2CwbRepo%7Coojs-ui.styles.icons-editing-core&skin=vector-2022&version=1egjk
02:00:55.706  HTTP    200 GET browser direct https://en.wikipedia.org/static/favicon/wikipedia.ico
02:00:55.706  HTTP    202 POST browser direct https://en.wikipedia.org/ins-502b/v2/events?hasty=true
02:00:55.710  HTTP    200 GET browser direct https://en.wikipedia.org/w/load.php?lang=en&modules=ext.cite.referencePreviews%7Cext.math.popup%7Cext.popups.main&skin=vector-2022&version=zzdks
02:00:55.719  HTTP    200 GET browser direct https://auth.wikimedia.org/metawiki/wiki/Special:CentralAutoLogin/checkLoggedIn?useformat=desktop&wikiid=enwiki&usesul3=1&type=script
02:00:56.251  HTTP    ERR CONNECT egress direct content-autofill.googleapis.com:443 error=blocked: noise BLOCKED=noise
02:00:56.542  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
02:00:56.899  HTTP    ERR CONNECT egress direct content-autofill.googleapis.com:443 error=blocked: noise BLOCKED=noise
02:01:00.200  HTTP    ERR CONNECT egress direct content-autofill.googleapis.com:443 error=blocked: noise BLOCKED=noise
02:01:02.983  HTTP    ERR CONNECT egress direct www.google.com:443
02:01:03.812  HTTP    ERR CONNECT egress direct content-autofill.googleapis.com:443 error=blocked: noise BLOCKED=noise
02:01:04.217  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
02:01:07.736  NOTE    result submitted: 2 verified, 0 cited_missing, 1 not_verified
```
