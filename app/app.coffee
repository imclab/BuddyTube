express = require 'express'
getYouTubeID = require 'get-youtube-id'
youtube = require 'youtube-feeds'
app = express()
port = 3000
app.set 'views', "#{ __dirname  }/views"
app.set 'view engine', 'jade'
app.engine 'jade', require('jade').__express

{detect, map, isEmpty, without} = require 'underscore'

app.get '/', (req, res) ->
  res.render 'chatroom'

app.use express.static("#{ __dirname }/public")

playlist = []
connections = []

io = require('socket.io').listen(app.listen(port))

io.sockets.on 'connection', (socket) ->
  connection = new ConnectionHandler(this, socket)
  connection.master = true if isEmpty(connections)
  addConnection(connection)


addConnection = (connection) ->
  connections.push(connection)

removeConnection = (connection) ->
  connections = without(connections, connection)

getMasterConnection = ->
  detect(connections, (connection) -> connection.isMaster())

getAllUsernames = ->
  map(connections, (connection) -> connection.username)

getCurrentVideo = ->
  getMasterVideo() || getDefaultVideo()

getNextVideo = ->
  if isEmpty(playlist)
    getDefaultVideo()
  else
    popVideoOffQueue(playlist)

popVideoOffQueue = (videos) ->
  id: playlist.shift()

getMasterVideo = ->
  return unless master = getMasterConnection()
  return unless master.currentVideoId?

  id: master.currentVideoId
  time: master.currentVideoTime

# Bwaaamp bwamp bwamp bwamp bwamp bwwaaaaamp.
getDefaultVideo = ->
  id: "ah4VQXe8YqU"

class ConnectionHandler

  constructor: (@sockets, @socket) ->
    @socket.on 'addUser',       @addUser
    @socket.on 'playerData',    @savePlayerData
    @socket.on 'chat',          @updateChat
    @socket.on 'disconnect',    @disconnect
    @socket.on 'videoAdded',    @addVideo
    @socket.on 'videoFinished', @playNextVideo

    @emitToAll 'updatePlaylist', playlist

  emitToAll: (args...) =>
    @sockets.emit(args...)

  emitToMyself: (args...) =>
    @socket.emit(args...)

  emitToOthers: (args...) =>
    @socket.broadcast.emit(args...)

  isMaster: =>
    !!@master

  addUser: (username) =>
    @username = username

    @emitToAll 'updateUsers', getAllUsernames()
    @emitToOthers 'updateChat', 'Playlist', "#{username} has connected"
    @emitToMyself 'updateChat', 'Playlist', 'you have connected'
    @emitToMyself 'playVideo', getCurrentVideo()

  savePlayerData: (data) =>
    @currentVideoId = data.videoID
    @currentVideoTime = data.currentTime

  addVideo: (video) =>
    id = getYouTubeID(video)

    playlist.push(id)

    @emitToAll 'updatePlaylist', playlist
    @emitToOthers 'updateChat', 'Playlist', "#{@username} added #{id} to the playlist"
    @emitToMyself 'updateChat', 'Playlist', "You added #{id} to the playlist"

  updateChat: (data) =>
    @emitToAll 'updateChat', @username, data

  disconnect: =>
    removeConnection(this)
    @emitToAll 'updateUsers', getAllUsernames()
    @emitToOthers 'updateChat', 'Playlist', "#{@username} has disconnected"

  playNextVideo: =>
    if @isMaster()
      @emitToAll 'playVideo', getNextVideo()
      @emitToAll 'updatePlaylist', playlist


console.log "listening on port #{port}"
