# Create new node module
# =================================================


# Node modules
# -------------------------------------------------

# include base modules
async = require 'async'
fs = require 'fs-extra'
path = require 'path'
colors = require 'colors'
{execFile} = require 'child_process'
request = require 'request'
prompt = require 'prompt'

# Main routine
# -------------------------------------------------
#
# __Arguments:__
#
# * `commander`
#   Commander instance for reading options.
# * `command`
#   Command specific parameters and options.
# * `callback(err)`
#   The callback will be called just if an error occurred or with `null` if
#   execution finished.
module.exports.run = (commander, command, cb) ->
  prompt.start()
  async.series [
    (cb) -> createDir commander, command, cb
    (cb) -> initGit commander, command, cb
    (cb) -> createGitHub commander, command, cb
    # init github
    (cb) -> createPackage commander, command, cb
    (cb) -> createReadme commander, command, cb
    (cb) -> createChangelog commander, command, cb
    (cb) -> initialCommit commander, command, cb
  ], (err) ->
    throw err if err
    console.log "You may now work with the new package.".yellow
    cb()

# ### Create the directory
createDir = (commander, command, cb) ->
  # check if directory already exist
  if fs.existsSync command.dir
    if commander.verbose
      console.log "Directory #{command.dir} already exists.".grey
    return cb()
  # create directory
  console.log "Create directory #{command.dir}"
  fs.mkdirs path.join(command.dir, 'src'), (err) ->
    return cb err if err
    # create .npmignore file
    file = path.join command.dir, '.npmignore'
    fs.writeFile file, """
      .project
      .settings
      .DS_Store
      *.sublime-*
      src
      doc
      coverage
      """, cb

# ### Create initial git repository
# It will set the `command.git` variable to the local uri
initGit = (commander, command, cb) ->
  # check for existing git repository
  if commander.verbose
    console.log "Check for configured git".grey
  if fs.existsSync path.join command.dir, '.git'
    command.git = 'file://' + fs.realpath command.dir
    return cb()
  # create a new repository
  prompt.get
    message: "Should a git repository be initialized?"
    validator: /y[es]*|n[o]?/,
    warning: 'You must respond with yes or no',
    default: 'yes'
  , (err, input) ->
    return cb err if err or not input.question is 'yes'
    console.log "Init new git repository"
    execFile "git", [ 'init' ], { cwd: command.dir }, (err, stdout, stderr) ->
      console.log stdout.trim().grey if stdout and commander.verbose
      console.error stderr.trim().magenta if stderr
      file = path.join command.dir, '.gitignore'
      return cb err if err or fs.existsSync file
      command.git = 'file://' + fs.realpath command.dir
      fs.writeFile file, """
        .project
        .settings
        .DS_Store
        *.sublime-*
        /node_modules/
        /doc/
        /coverage/
        /lib/
        """, cb

# ### Create new GitHub repository if not existing
# It will set the `command.github` variable
createGitHub = (commander, command, cb) ->
  return cb() if command.private
  # check for existing package with github url
  if commander.verbose
    console.log "Check for configured github".grey
  file = path.join command.dir, 'package.json'
  if fs.existsSync file
    pack = JSON.parse fs.readFileSync file
    unless pack.repository.type is 'git'
      console.out "Only git repositories can be added to github.".yellow
      return cb()
    if ~pack.repository.url.indexOf 'github.com/'
      command.github = pack.repository.url
      return cb()
  # create github repository
  prompt.get
    message: "Should a github repository be initialized?"
    validator: /y[es]*|n[o]?/,
    warning: 'You must respond with yes or no',
    default: 'yes'
  , (err, input) ->
    return cb err if err or not input.question is 'yes'
    console.log "Init new git repository"
    prompt. [{
      message: "GitHub username:"
      name: 'username'
      required: true
      default: 'alinex'
    }, {
      message: "Password for GitHub login:"
      name: 'password'
      hidden: true
      required: true
    }, {
      message: "Give a short description of this module."
      name: 'description'
      required: true
    }], function (err, input) ->
      console.log result
      process.exit 1

      gitname = path.basename command.dir
      command.github = "https://github.com/#{input.username}/#{gitname}"
      request {
        uri: "https://api.github.com/repos/#{gituser}/#{gitname}"
        auth:
          user: input.username
          pass: input.password
        headers:
          'User-Agent': input.username
      }, (err, response, body) ->
        return cb err if err
        answer = JSON.parse response.body
        unless answer.message?
          return cb()
        unless answer.message is 'Not Found'
          return cb answer.message
        console.log "Create new GitHub repository"
        request {
          uri: "https://api.github.com/user/repos"
          auth:
            user: input.username
            pass: input.password
          headers:
            'User-Agent': input.username
          method: 'POST'
          body: JSON.stringify
            name: gitname
            description: input.description
            homepage: "http://#{input.username}.github.io/#{gitname}"
            private: false
            has_issues: true
            has_wiki: false
            has_downloads: true
        }, (err, response, body) ->
          return cb err if err
          unless response?.statusCode is 201
            return cb "GitHub status was #{response.statusCode} in try to create repository"
          console.log "Connect with GitHub repository"
          execFile "git", [
            'remote'
            'add', 'origin', command.git
          ], { cwd: command.dir }, (err, stdout, stderr) ->
            console.log stdout.trim().grey if stdout and commander.verbose
            console.error stderr.trim().magenta if stderr
            cb err

# ### Create new package.json
createPackage = (commander, command, cb) ->
  # check if package.json exists
  if commander.verbose
    console.log "Check for existing package.json".grey
  file = path.join command.dir, 'package.json'
  if fs.existsSync file
    console.log "Skipped package.json creation, because already exists".yellow
    return cb()
  console.log "Create new package.json file"
  gitname = path.basename command.dir
  gituser = path.basename path.dirname command.github
  pack =
    name: command.package
    version: '0.0.0'
    description: ''
    copyright: PKG.copyright
    private: command.private ? false
    keywords: ''
    homepage: if command.github then "http://#{gituser}.github.io/#{gitname}/" else ""
    repository:
      type: 'git'
      url: command.git
    bugs: if command.github then "#{command.git}/issues" else ""
    author: PKG.author
    contributors: []
    license: PKG.license
    main: './lib/index.js'
    scripts:
      prepublish: "node_modules/.bin/coffee -c -m -o lib src"
    directories:
      lib: './lib'
    dependencies: {}
    devDependencies:
      "coffee-script": ">=1.7.0"
    optionalDependencies: {}
    engines: PKG.engines
    os: []
  fs.writeFile file, JSON.stringify(pack, null, 2), cb

# ### Create a README.md file
createReadme = (commander, command, cb) ->
  if commander.verbose
    console.log "Check for README.md".grey
  file = path.join command.dir, 'README.md'
  if fs.existsSync file
    return cb()
  console.log "Create new README.md file"
  gitname = path.basename command.dir
  gituser = path.basename path.dirname command.github
  doc =
    badges: ''
    install: ''
  if command.github
    doc.badges = "\n[![Build Status]
    (https://travis-ci.org/alinex/node-error.svg?branch=master)]
    (https://travis-ci.org/alinex/node-error)
    \n[![Coverage Status]
    (https://coveralls.io/repos/alinex/node-error/badge.png?branch=master)]
    (https://coveralls.io/r/alinex/node-error?branch=master)"
  unless command.private
    doc.badges += "\n[![Dependency Status]
    (https://gemnasium.com/alinex/node-error.png)]
    (https://gemnasium.com/alinex/node-error)"
    doc.install = "\n[![NPM](https://nodei.co/npm/#{command.package}.png?downloads=true&stars=true)]
    (https://nodei.co/npm/#{command.package}/)"

  fs.writeFile file, """
    Package: #{command.package}
    =================================================
    #{doc.badges}

    Description comes here...


    Install
    -------------------------------------------------
    #{doc.install}

    License
    -------------------------------------------------

    Copyright #{(new Date()).getFullYear()} Alexander Schilling

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

    >  <http://www.apache.org/licenses/LICENSE-2.0>

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.

    """, cb

# ### Create an initial changelog
createChangelog = (commander, command, cb) ->
  if commander.verbose
    console.log "Check for existing changelog".grey
  file = path.join command.dir, 'Changelog.md'
  if fs.existsSync file
    return cb()
  console.log "Create new changelog file"
  fs.writeFile file, """
    Version changes
    =================================================

    The following list gives a short overview about what is changed between
    individual versions:


    """, cb

# ### Make initial commit
initialCommit = (commander, command, cb) ->
  if commander.verbose
    console.log "Check if git already used".grey
  execFile "git", [ 'log' ], { cwd: command.dir }, (err, stdout, stderr) ->
    return cb() if stdout.trim()
    console.log "Initial commit"
    execFile "git", [ 'add', '*' ], { cwd: command.dir }, (err, stdout, stderr) ->
      console.log stdout.trim().grey if stdout and commander.verbose
      console.error stderr.trim().magenta if stderr
      execFile "git", [ 'commit', '-m', 'Initial commit' ]
      , { cwd: command.dir }, (err, stdout, stderr) ->
        console.log stdout.trim().grey if stdout and commander.verbose
        console.error stderr.trim().magenta if stderr
        console.log "Push to origin"
        execFile "git", [ 'push', 'origin', 'master' ],
        { cwd: command.dir }, (err, stdout, stderr) ->
          console.log stdout.trim().grey if stdout and commander.verbose
          console.error stderr.trim().magenta if stderr
          cb()
