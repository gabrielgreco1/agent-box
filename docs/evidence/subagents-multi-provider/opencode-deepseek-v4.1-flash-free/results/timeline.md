# Timeline: example-com

```
05:55:03.192  HTTP    ERR GET egress direct http://clients2.google.com/time/1/current?cup2key=[redacted]&cup2hreq=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 error=blocked: noise BLOCKED=noise
05:55:03.243  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
05:55:03.248  HTTP    ERR CONNECT egress direct update.googleapis.com:443 error=blocked: noise BLOCKED=noise
05:55:04.083  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
05:55:06.759  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
05:55:09.175  HTTP    ERR CONNECT egress direct mtalk.google.com:5228
05:55:13.227  HTTP    ERR CONNECT egress direct www.google.com:443
05:55:14.831  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
05:55:15.296  PLAN    Open https://example.com in the browser, read the page title, then result_submit with url/title/evidence request ids.
05:55:18.388  DOING   Opening https://example.com in the headless browser.
05:55:22.601  HTTP    200 GET browser direct https://example.com/
05:55:22.668  HTTP    200 GET browser direct https://example.com/s.js
05:55:37.551  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
05:55:40.017  FOUND   https://example.com/ returned HTTP 200 with document.title "Example Domain" (confirmed via browser_eval).  [evidence: 01M5BY1WJA9S1HADN2FWPFKDQV]
05:55:47.345  NOTE    result submitted: 3 verified, 0 cited_missing, 1 not_verified
```
