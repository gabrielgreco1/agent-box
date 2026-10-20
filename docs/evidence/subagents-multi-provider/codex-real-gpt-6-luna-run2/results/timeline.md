# Timeline: example-com

```
06:05:37.846  HTTP    ERR GET egress direct http://clients2.google.com/time/1/current?cup2key=[redacted]&cup2hreq=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 error=blocked: noise BLOCKED=noise
06:05:37.865  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
06:05:37.871  HTTP    ERR CONNECT egress direct update.googleapis.com:443 error=blocked: noise BLOCKED=noise
06:05:38.736  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
06:05:41.312  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
06:05:44.315  PLAN    Open https://example.com in the assigned browser, read its document title, submit the title with the browser request id as evidence.
06:05:45.330  DOING   Navigating to https://example.com.
06:05:46.491  HTTP    200 GET browser direct https://example.com/
06:05:46.516  HTTP    200 GET browser direct https://example.com/s.js
06:05:48.134  HTTP    ERR CONNECT egress direct www.google.com:443
06:05:48.798  HTTP    ERR CONNECT egress direct accounts.google.com:443 error=blocked: noise BLOCKED=noise
06:05:51.783  FOUND   Browser navigation returned document title Example Domain.  [evidence: 01M5BYMY18JHQ8JFDGBC7JK9KY]
06:05:53.213  NOTE    result submitted: 1 verified, 0 cited_missing, 0 not_verified
```
