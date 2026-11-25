# Cloud Functions (dormant)

`onContentUploaded` sends a push notification to students when a tutor uploads
content. **Cloud Functions require the Blaze plan**, so this is not deployed while
the project runs on the free Spark plan, and `firebase.json` deliberately has no
`functions` block so `firebase deploy` cannot try to ship it.

To enable it later: upgrade to Blaze, add
`"functions": { "source": "functions" }` back to `firebase.json`, and deploy.
