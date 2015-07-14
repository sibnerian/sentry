module.exports = (dependencies) ->
  {
    packages: {lodash: _, express, async},
    middleware: {auth, getUserRepos},
    lib: {githubAPI, githubCredsFor},
    config
  } = dependencies
  router = express.Router()
  return (app) ->
    addRepo = (req, res, next) ->
      {user, params: {repo}} = req
      collaboratorData =
        user: user.profile.username
        collabuser: config.github.BOT_USERNAME
        repo: repo
      hookData =
        user: user.profile.username
        name: 'web'
        events: ['push']
        active: true
        config:
          url: config.server.WEBHOOK_URL
          content_type: 'json'
          insecure_ssl: 1
        repo: repo
      githubAPI(githubCredsFor user).repos.addCollaborator collaboratorData, (collaboratorError) ->
        return next(collaboratorError) if collaboratorError
        githubAPI(githubCredsFor user).repos.createHook hookData, (hookError, result) ->
          return next(hookError) if hookError
          user.repos ?= []
          user.repos.push {name: repo, hookId: result.id}
          user.save(next)
    # TODO implement this later, not necessary for now
    removeComments = (req, res, next) ->
      next()

    removeWebhook = (req, res, next) ->
      {user, params: {repo}} = req
      {hookId} = _.findWhere user.repos, {name: repo}
      hookDeleteData =
        user: user.profile.username
        id: hookId
        repo: repo
      githubAPI(githubCredsFor user).repos.deleteHook(hookDeleteData, next)

    removeBot = (req, res, next) ->
      {user, params: {repo}} = req
      collaboratorData =
        user: user.profile.username
        collabuser: config.github.BOT_USERNAME
        repo: repo
      githubAPI(githubCredsFor user).repos.removeCollaborator(collaboratorData, next)

    removeFromUserRepos = (req, res, next) ->
      {user, params: {repo}} = req
      user.repos = _.reject user.repos, {name: repo}
      user.save(next)

    webhookAll = (req, res, next) ->
      if req.get('X-GitHub-Event') is 'ping'
        return res.send {success: true}
      async.each(
        plugins,
        ((plugin, done) ->
          pushdata = req.body
          plugin.handlePush(pushdata, done)),
        ((error) -> res.send (if err then {error} else {success: true}))
      )

    sendSuccess = (req, res) -> res.send {success: true}

    router.post '/addRepo/:repo', addRepo, sendSuccess
    router.post '/removeRepo/:repo', removeComments, removeWebhook, removeBot, removeFromUserRepos, sendSuccess
    router.post '/webhook/all', webhookAll

    app.use '/api', router