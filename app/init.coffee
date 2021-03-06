module.exports = (dependencies) ->
  {
    lib: {db, getActiveStatusForRepo, repoQueueWorker, queueMap},
    packages, config, controllers
  } = dependencies
  {server: {ROOT, APP_ROOT, COOKIE_SECRET, CALLBACK_URL}, github: {CLIENT_ID, CLIENT_SECRET}, plugins} = config
  {lodash: _, 'body-parser': bodyParser, 'cookie-parser': cookieParser, 'express-session': session, 'connect-flash': flash
   , 'express-handlebars': exphbs, 'express-validator': expressValidator, 'passport-local': passportLocal, 'serve-favicon': favicon
   , glob, passport, express, path, handlebars, morgan, url, async} = packages
  User = db.model('User')
  ActiveRepo = db.model('ActiveRepo')
  return (app) ->

    # Initialize all plugins and sources
    initPlugins = {}
    {sources, services} = plugins
    serverConfig = config.server
    initPlugins.sources = _.map sources, (Source) ->
      instance = new Source {serverConfig, packages, config: config[Source.NAME]}
      return _.extend instance, Source
    initPlugins.services = _.map services, (Service) ->
      instance = new Service {db, packages, serverConfig, config: config[Service.NAME], sources: initPlugins.sources}
      return _.extend instance, Service

    # See https://github.com/expressjs/body-parser/issues/100
    app.use (req, res, next) ->
      if req.headers?['content-encoding'] is 'utf-8' or req.headers?['content-encoding'] is 'UTF-8'
        delete req.headers['content-encoding']
      next()

    app.disable 'x-powered-by'
    app.set 'views', path.join(APP_ROOT, 'views')
    app.engine '.hbs', exphbs(
      extname: '.hbs'
      defaultLayout: 'layout'
      handlebars: handlebars
      layoutsDir: path.join(APP_ROOT, 'views', 'layouts')
      partialsDir: path.join(APP_ROOT, 'views', 'partials')
      # coffeelint: disable=missing_fat_arrows
      helpers:
        toJSON: (obj) -> JSON.stringify(obj, null, '  ')
        section: (name, options) ->
          @_sections ?= {}
          @_sections[name] = options.fn(@)
          return null
        renderSection: (name) -> if @_sections?[name]? then new handlebars.SafeString(@_sections[name]) else ''
        # coffeelint: enable=missing_fat_arrows
    )
    app.set 'view engine', '.hbs'
    app.set 'port', process.env.PORT || 3000
    app.use favicon(path.join ROOT, '/public/favicons/favicon.ico')
    app.use bodyParser.urlencoded({extended: false, limit: '50mb'})
    app.use bodyParser.json({limit: '50mb'})
    app.use expressValidator()
    app.use cookieParser(COOKIE_SECRET)
    app.use session(
      secret: COOKIE_SECRET
      cookie: {maxAge: 1000 * 60 * 60}
      saveUninitialized: true
      resave: true
    )

    app.use flash()
    app.use (req, res, next) ->
      res.locals.successFlashes = req.flash 'success'
      res.locals.errorFlashes = req.flash 'error'
      res.locals.hasFlashes = (res.locals.successFlashes.length > 0) or (res.locals.errorFlashes.length > 0)
      next()

    app.use passport.initialize()
    app.use passport.session()

    localStrategy = new passportLocal.Strategy (username, password, done) ->
      User.findOne {username}, (err, user) ->
        return done(err) if err
        return done(null, false) if not user? or not user.verifyPassword(password)
        done(null, user)

    passport.use localStrategy

    passport.serializeUser (user, done) -> done(null, user._id)
    passport.deserializeUser (_id, done) -> User.findOne({_id}).exec(done)

    app.use '/static', express.static(path.join ROOT, '/public')
    app.use morgan('dev')

    app.use (req, res, next) ->
      res.locals.user = req.user
      next()

    _.forEach initPlugins.sources, (source) ->
      source.on 'hook', ({repoId}) ->
        console.log "Running hooks for #{repoId}..."
        ActiveRepo.find {repoId, sourceName: source.NAME}, (mongoError, docs) ->
          return console.error(mongoError, mongoError.stack) if mongoError
          _.each docs, (activeRepo) ->
            repoIdString = activeRepo._id.toString()
            queueMap[repoIdString] ?= async.queue(repoQueueWorker, 1)
            queueMap[repoIdString].push {repo: activeRepo, initPlugins}, (queueProcessErr) ->
              if queueProcessErr?
                msg = "Error handling #{repoIdString} for #{activeRepo.repoId}"
                return console.error msg, queueProcessErr, queueProcessErr.stack
              console.log "Handled hook repo data (#{source.NAME}, #{activeRepo.repoId}) successfully!"

    _.forEach controllers, (controller) ->
      controller({app, initPlugins})



    app.use (req, res, next) ->
      err = new Error('Not Found')
      err.status = 404
      next(err)

    app.use (err, req, res, next) ->
      console.error("Error processing #{req.originalUrl}")
      console.error(err)
      err.status ?= 500
      err.stack = if app.get('env') is 'development' then err.stack else ''
      res.status(err.status).render 'error', {layout: false, error: err}
