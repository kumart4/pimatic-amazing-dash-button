# The amazing dash-button plugin
module.exports = (env) ->

  Promise = env.require 'bluebird'
  cap = require 'cap'
  commons = require('pimatic-plugin-commons')(env)


  # ###AmazingDashButtonPlugin class
  class AmazingDashButtonPlugin extends env.plugins.Plugin

    init: (app, @framework, @config) =>
      @interfaceAddress = @config.interfaceAddress if @config.interfaceAddress?
      @invert = @config.invert || false
      @_contact = @invert
      @debug = @config.debug || false
      @base = commons.base @, 'Plugin'
      @capture = new cap.Cap()
      @buffer = new Buffer(65536)

      process.on "SIGINT", @_stop
      @_start()

      # register devices
      deviceConfigDef = require("./device-config-schema")
      @framework.deviceManager.registerDeviceClass("AmazingDashButton",
        configDef: deviceConfigDef.AmazingDashButton,
        createCallback: (@config, lastState) =>
          new AmazingDashButton(@config, @, lastState)
      )

      # auto-discovery
      @framework.deviceManager.on('discover', (eventData) =>
        @framework.deviceManager.discoverMessage 'pimatic-amazing-dash-button', 'Searching for dash-buttons. Press dash-button now!'
        @candidatesSeen = []
        @lastId = null

        @arpPacketHandler = (arp) =>
          candidateArp = arp.info.srcmac.toUpperCase()
          strippedArpTrunc = candidateArp.replace(/:/g,'').substring(0,6)

          # List of registered Mac addresses with IEEE as of 18 July 2016 for Amazon Technologies Inc.
          # source: https://regauth.standards.ieee.org/standards-ra-web/pub/view.html#registries
          amazonVendorIds = [
            "747548", "F0D2F1", "8871E5", "74C246", "F0272D", "0C47C9",
            "A002DC", "AC63BE", "44650D", "50F5DA", "84D6D0"
          ]
          if strippedArpTrunc in amazonVendorIds and candidateArp not in @candidatesSeen
            @base.debug 'Amazon device (possibly a dash-button) detected: ' + candidateArp
            @candidatesSeen.push candidateArp
            @lastId = @base.generateDeviceId @framework, "dash", @lastId

            deviceConfig =
              id: @lastId
              name: @lastId
              class: 'AmazingDashButton'
              macAddress: candidateArp

            @framework.deviceManager.discoveredDevice(
              'pimatic-amazing-dash-button', "#{deviceConfig.name} (#{deviceConfig.macAddress})", deviceConfig
            )

        @on 'arpPacket', @arpPacketHandler
        @timer = setTimeout( =>
          @removeListener 'arpPacket', @arpPacketHandler
        , eventData.time
        )
      )

    _start: () ->
      if @interfaceAddress?
        device = cap.findDevice @interfaceAddress
      else
        device = cap.findDevice()
      @base.debug "Sniffing for ARP requests on device", device

      linkType = @capture.open device, 'arp', 10 * 1024 * 1024, @buffer
      try
        @capture.setMinBytes 0
      catch e
        @_base.debug e

      @capture.on "packet", @_rawPacketHandler

    _stop: () =>
      @capture.removeListener "packet", @_rawPacketHandler
      @capture.close();

    _rawPacketHandler: () =>
      ret = cap.decoders.Ethernet @buffer
      @emit 'arpPacket', ret if ret.info.type is 2054

  class AmazingDashButton extends env.devices.ContactSensor
    # Initialize device by reading entity definition from middleware
    constructor: (@config, @plugin, lastState) ->
      @id = @config.id
      @name = @config.name
      @macAddress = @config.macAddress.toUpperCase()
      @_invert = @config.invert || false
      @_contact = @_invert
      @debug = @plugin.debug || false
      @base = commons.base @, @config.class
      @arpPacketHandler = (arp) =>
        if arp.info.srcmac.toUpperCase() is @macAddress
          @_setContact not @_invert
          clearTimeout @timer if @timer?
          @timer = setTimeout( =>
            @_setContact @_invert
            @timer = null
          , @config.holdTime
          )
      super()
      @plugin.on 'arpPacket', @arpPacketHandler

    destroy: () ->
      clearTimeout @timer if @timer?
      @plugin.removeListener 'arpPacket', @arpPacketHandler
      super()

    getContact: () -> Promise.resolve @_contact


  # ###Finally
  # Create a instance of my plugin
  # and return it to the framework.
  return new AmazingDashButtonPlugin