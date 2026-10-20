# Timeline: example-title

```
06:07:14.940  HTTP    ERR GET egress direct http://clients2.google.com/time/1/current?cup2key=[redacted]&cup2hreq=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 error=blocked: noise BLOCKED=noise
06:07:14.958  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
06:07:14.963  HTTP    ERR CONNECT egress direct update.googleapis.com:443 error=blocked: noise BLOCKED=noise
06:07:15.886  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
06:07:18.369  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
06:07:25.037  HTTP    ERR CONNECT egress direct www.google.com:443
06:07:26.820  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
06:07:27.872  PLAN    Claimed example-title box. Step 1: open https://example.com in browser. Step 2: read document.title via browser_eval / read for full title text. Step 3: submit result {"page_title","url"} with citation to the request id of the page load.
06:07:29.509  DOING   Opening https://example.com in the headless browser and waiting for full load.
06:07:30.902  HTTP    200 GET browser direct https://example.com/
06:07:30.923  HTTP    200 GET browser direct https://example.com/s.js
06:07:51.996  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
06:07:53.567  FOUND   https://example.com loaded fully (readyState=complete, HTTP 200) with document.title = "Example Domain". Evidence: request id 01M5BYR40WV1NE56P6RYE7JSBF (browser_open) + browser_eval confirming document.title.  [evidence: 01M5BYR40WV1NE56P6RYE7JSBF]
06:08:13.106  NOTE    result submitted: 2 verified, 0 cited_missing, 0 not_verified
06:08:14.945  HTTP    ERR CONNECT egress direct update.googleapis.com:443 error=blocked: noise BLOCKED=noise
```
