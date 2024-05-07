# onnxruntime-python-alpine

A dockerfile supporting onnxruntime with Python bindings on Alpine Linux

## Notes:

- This could break with upstream changes. I might pin commits for the dependencies of this.

- It's going to take a while to build. The only way I could get onnxruntime to compile was to not parallelize it. Weird, but it works.

  - I'm not sure exactly how long it would take to build due to caching, but my estimate would be roughly 2 hours starting fresh. 

- If you intend on using this, I would recommend using the prebuilt image unless onnxruntime is out of date for you.