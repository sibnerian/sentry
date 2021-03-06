module.exports = (dependencies) ->
  {packages: {async, child_process, path, lodash: _}, lib: {repoPathFor, getMatchingFiles}, config} = dependencies
  return ({repo, initPlugins: {services, sources}, serviceToInitialize}, callback) ->
    repoPath = repoPathFor repo
    {sourceName, configObject, activeServices} = repo
    sshKeypath = config[sourceName]?.SSH_KEYPATH
    gitCommand = if sshKeypath? then "sh #{path.join config.server.ROOT, 'scripts/git.sh'} -i #{sshKeypath}" else 'git'
    child_process.exec "#{gitCommand} fetch --all && #{gitCommand} pull --all", {cwd: repoPath}, (err, stdout, stderr) ->
      return callback(err) if err?
      if serviceToInitialize?
        serviceName = serviceToInitialize.NAME
        getMatchingFiles {repoPath, serviceName, configObject}, (err, files) ->
          return callback(err) if err?
          serviceToInitialize.handleInitialRepoData {files, repoPath, repoModel: repo, repoConfig: configObject?[serviceName]}, callback
      else
        async.each activeServices, ((serviceName, eachCallback) ->
          service = _.findWhere services, {NAME: serviceName}
          getMatchingFiles {repoPath, serviceName, configObject}, (err, files) ->
            return eachCallback(err) if err
            service.handleHookRepoData {files, repoPath, repoModel: repo, repoConfig: configObject?[serviceName]}, eachCallback
        ), callback
