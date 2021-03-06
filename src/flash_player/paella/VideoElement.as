package paella {
	
import flash.display.Sprite;
import flash.events.*;
import flash.net.NetConnection;
import flash.net.NetStream;
import flash.media.Video;
import flash.media.SoundTransform;
import flash.utils.Timer;

public class VideoElement extends Sprite implements IMediaElement {
	private var _javascriptInterface:JavascriptInterface;
	
	private var _currentUrl:String = "";
	private var _autoplay:Boolean = true;
	private var _preload:Boolean = false;
	private var _isPreloading:Boolean = false;
	
	private var _connection:NetConnection;
	private var _stream:NetStream;
	private var _video:Video;
	private var _soundTransform:SoundTransform;
	private var _oldVolume:Number = 1;
	
	// event values
    private var _duration:Number = 0;
    private var _framerate:Number;
    private var _isPaused:Boolean = true;
    private var _isEnded:Boolean = false;
    private var _volume:Number = 1;
    private var _isMuted:Boolean = false;

	private var _bufferTime:Number = 1;
    private var _bytesLoaded:Number = 0;
    private var _bytesTotal:Number = 0;
    private var _bufferedTime:Number = 0;
    private var _bufferEmpty:Boolean = false;
    private var _bufferingChanged:Boolean = false;
    private var _seekOffset:Number = 0;


    private var _videoWidth:Number = -1;
    private var _videoHeight:Number = -1;

    private var _timer:Timer;

    private var _isRTMP:Boolean = false;
    private var _streamer:String = "";
    private var _isConnected:Boolean = false;
    private var _playWhenConnected:Boolean = false;
    private var _hasStartedPlaying:Boolean = false;

    private var _parentReference:Object;
    private var _pseudoStreamingEnabled:Boolean = false;
    private var _pseudoStreamingStartQueryParam:String = "start";
	
    public function setReference(arg:Object):void { _parentReference = arg; }
	public function setSize(width:Number, height:Number):void { _video.width = width; _video.height = height; }
    public function setPseudoStreaming(enablePseudoStreaming:Boolean):void { _pseudoStreamingEnabled = enablePseudoStreaming; }
    public function setPseudoStreamingStartParam(pseudoStreamingStartQueryParam:String):void { _pseudoStreamingStartQueryParam = pseudoStreamingStartQueryParam; }
	public function get video():Video { return _video; }
	public function get videoHeight():Number { return _videoHeight; }
	public function get videoWidth():Number { return _videoWidth; }
	public function duration():Number { return _duration; }
	
	public function currentProgress():Number {
		if(_stream != null) {
			return Math.round(_stream.bytesLoaded/_stream.bytesTotal*100);
	    } else {
			return 0;
	    }
	}
	
	public function currentTime():Number {
		var currentTime:Number = 0;
	    if (_stream != null) {
			currentTime = _stream.time;
			if (_pseudoStreamingEnabled) {
				currentTime += _seekOffset;
			}
		}
	    return currentTime;
	}
	
	public function setAutoplay(autoplay:Boolean):void { _playWhenConnected = autoplay; }
	
    public function VideoElement(jsInterface:JavascriptInterface, autoplay:Boolean, preload:Boolean, timerRate:Number, startVolume:Number, streamer:String, bufferTime:Number) {
		_javascriptInterface = jsInterface;
		_playWhenConnected = true;
		_bufferTime = bufferTime;
		
		_autoplay = autoplay;
		_volume = startVolume;
		_preload = preload;
		_streamer = streamer;

		_video = new Video();
		addChild(_video);

		_connection = new NetConnection();
		_connection.client = { onBWDone: function():void{} };
		_connection.addEventListener(NetStatusEvent.NET_STATUS, netStatusHandler);
		_connection.addEventListener(SecurityErrorEvent.SECURITY_ERROR, securityErrorHandler);

		_timer = new Timer(timerRate);
		_timer.addEventListener("timer", timerHandler);
		
		_timer.start();
    }
	
	public function set bufferTime(time:Number):void {
		_bufferTime = time;
	}
	
	public function get bufferTime():Number {
		return _bufferTime;
	}
	
	private function timerHandler(e:TimerEvent):void {
		_bytesLoaded = _stream.bytesLoaded;
	    _bytesTotal = _stream.bytesTotal;

	    if (!_isPaused) {
			sendEvent(HtmlEvent.TIMEUPDATE);
	    }
		
	    if (_bytesLoaded < _bytesTotal) {
	    	sendEvent(HtmlEvent.PROGRESS);
	    }
	}
	
	private function netStatusHandler(event:NetStatusEvent):void {
	    switch (event.info.code) {

	      case "NetStream.Buffer.Empty":
	        _bufferEmpty = true;
	        _isEnded ? sendEvent(HtmlEvent.ENDED) : null;
	        break;

	      case "NetStream.Buffer.Full":
	        _bytesLoaded = _stream.bytesLoaded;
	        _bytesTotal = _stream.bytesTotal;
	        _bufferEmpty = false;

	        sendEvent(HtmlEvent.PROGRESS);
	        break;

	      case "NetConnection.Connect.Success":
	        connectStream();
			sendEvent(HtmlEvent.LOADEDDATA);
	        sendEvent(HtmlEvent.CANPLAY);
	        break;
	      case "NetStream.Play.StreamNotFound":
	        JavascriptTrace.error("Unable to locate video");
	        break;

	      // STREAM
	      case "NetStream.Play.Start":
	        _isPaused = false;
	        sendEvent(HtmlEvent.LOADEDDATA);
	        sendEvent(HtmlEvent.CANPLAY);

	        if (!_isPreloading) {
	          sendEvent(HtmlEvent.PLAY);
	          sendEvent(HtmlEvent.PLAYING);
	        }

	        break;

	      case "NetStream.Seek.Notify":
	        sendEvent(HtmlEvent.SEEKED);
	        break;

	      case "NetStream.Pause.Notify":
	        _isPaused = true;
	        sendEvent(HtmlEvent.PAUSE);
	        break;

	      case "NetStream.Play.Stop":
	        _isEnded = true;
	        _isPaused = false;
	        _timer.stop();
	        _bufferEmpty ? sendEvent(HtmlEvent.ENDED) : null;
	        break;

	    }
	}
	
	private function securityErrorHandler(event:SecurityErrorEvent):void {
		JavascriptTrace.error("Security error: " + event);
	}

	private function asyncErrorHandler(event:AsyncErrorEvent):void {
	}
	
	private function onMetaDataHandler(info:Object):void {
	    // Only set the duration when we first load the video
	    if (_duration == 0) {
			_duration = info.duration;
	    }
	    _framerate = info.framerate;
	    _videoWidth = info.width;
	    _videoHeight = info.height;

	    // set size?
	    sendEvent(HtmlEvent.LOADEDMETADATA);

	    if (_isPreloading) {
			_stream.pause();
			_isPaused = true;
			_isPreloading = false;

			sendEvent(HtmlEvent.PROGRESS);
			sendEvent(HtmlEvent.TIMEUPDATE);
	    }
	}
	
	
	// IMediaElement
	public function setSrc(url:String):void {
		if (_isConnected && _stream) {
			_stream.pause();
		}
		
		_duration = 0;
		_currentUrl = url;
		_isRTMP = !!_currentUrl.match(/^rtmp(s|t|e|te)?\:\/\//) || _streamer != "";
		_isConnected = false;
		_hasStartedPlaying = false;
	}
	
	public function load():void {
		// disconnect existing stream and connection
		if (_isConnected && _stream) {
			_stream.pause();
			_stream.close();
			_connection.close();
		}
		_isConnected = false;
		_isPreloading = false;


		_isEnded = false;
		_bufferEmpty = false;

		// start new connection
		JavascriptTrace.debug("URL: " + _currentUrl);
		if (_isRTMP) {
			JavascriptTrace.debug("Playing RTMP video stream");
			var rtmpInfo:Object = parseRTMP(_currentUrl);
			if (_streamer != "") {
				rtmpInfo.server = _streamer;
				rtmpInfo.stream = _currentUrl;
			}
			_connection.connect(rtmpInfo.server);
		} else {
			JavascriptTrace.debug("Playing progressive download video");
			_connection.connect(null);
		}

		// in a few moments the "NetConnection.Connect.Success" event will fire
		// and call createConnection which finishes the "load" sequence
		sendEvent(HtmlEvent.LOADSTART);
	}
	
	public function connectStream():void {
		JavascriptTrace.debug("connectStream");
		
		_stream = new NetStream(_connection);

		// explicitly set the sound since it could have come before the connection was made
		_soundTransform = new SoundTransform(_volume);
		_stream.soundTransform = _soundTransform;

		// set the buffer to ensure nice playback
		_stream.bufferTime = this._bufferTime;
		_stream.bufferTimeMax = this._bufferTime * 2;

		_stream.addEventListener(NetStatusEvent.NET_STATUS, netStatusHandler); // same event as connection
		_stream.addEventListener(AsyncErrorEvent.ASYNC_ERROR, asyncErrorHandler);

		var customClient:Object = new Object();
		customClient.onMetaData = onMetaDataHandler;
		_stream.client = customClient;

		_video.attachNetStream(_stream);
		
		// start downloading without playing )based on preload and play() hasn't been called)
		// I wish flash had a load() command to make this less awkward
		if (_preload && !_playWhenConnected) {
			_isPaused = true;
			//stream.bufferTime = 20;
			_stream.play(getCurrentUrl(0), 0, 0);
			//_stream.pause();

			_isPreloading = true;

			//_stream.pause();
			//
			//sendEvent(HtmlEvent.PAUSE); // have to send this because the "playing" event gets sent via event handlers
		}

		_isConnected = true;

		if (_playWhenConnected && !_hasStartedPlaying) {
			play();
			//_playWhenConnected = false;
		}
	}
	
	public function play():void {
		/*if (!_hasStartedPlaying && !_isConnected) {
			_playWhenConnected = true;
			load();
			return;
		}*/

		if (_hasStartedPlaying) {
			if (_isPaused) {
				_stream.resume();
				_timer.start();
				_isPaused = false;
				sendEvent(HtmlEvent.PLAY);
				sendEvent(HtmlEvent.PLAYING);
			}
			else {
				JavascriptTrace.debug("No Esta pausado");
			}
			
		}
		else {

			if (_isRTMP) {
				var rtmpInfo:Object = parseRTMP(_currentUrl);
				_stream.play(rtmpInfo.stream);
			}
			else {
				_stream.play(getCurrentUrl(0));
			}
			_timer.start();
			_isPaused = false;
			_hasStartedPlaying = true;

			// don't toss play/playing events here, because we haven't sent a
			// canplay / loadeddata event yet. that'll be handled in the net
			// event listener
		}
	}
	
	public function pause():void {
		if (_stream == null)
			return;

		_stream.pause();
		_isPaused = true;

		if (_bytesLoaded == _bytesTotal) {
			_timer.stop();
		}

		_isPaused = true;
		sendEvent(HtmlEvent.PAUSE);
	}
	
	public function stop():void {
	    if (_stream == null)
	     	return;

	    _stream.close();
	    _isPaused = false;
	    _timer.stop();
	    sendEvent(HtmlEvent.STOP);
	}
	
	public function setCurrentTime(pos:Number):void {
		if (_stream == null) {
			return;
		}

		// Calculate the position of the buffered video
		var bufferPosition:Number = _bytesLoaded / _bytesTotal * _duration;

		if (_pseudoStreamingEnabled) {
			sendEvent(HtmlEvent.SEEKING);
			// Normal seek if it is in buffer and this is the first seek
			if (pos < bufferPosition && _seekOffset == 0) {
				_stream.seek(pos);
			}
			else {
				// Uses server-side pseudo-streaming to seek
				_stream.play(getCurrentUrl(pos));
				_seekOffset = pos;
			}
		}
		else {
			sendEvent(HtmlEvent.SEEKING);
			_stream.seek(pos);
		}

		if (!_isEnded) {
			sendEvent(HtmlEvent.TIMEUPDATE);
		}
	}
	
	public function setVolume(volume:Number):void {
		if (_stream != null) {
			_soundTransform = new SoundTransform(volume);
			_stream.soundTransform = _soundTransform;
		}

		_volume = volume;

		_isMuted = (_volume == 0);

		sendEvent(HtmlEvent.VOLUMECHANGE);
	}
	
	public function getVolume():Number {
	    if(_isMuted) {
	     	return 0;
	    }
		else {
	    	return _volume;
	    }
	}
	
	public function setMuted(muted:Boolean):void {
		if (_isMuted == muted)
			return;

		if (muted) {
			_oldVolume = (_stream == null) ? _oldVolume : _stream.soundTransform.volume;
			setVolume(0);
		}
		else {
			setVolume(_oldVolume);
		}

		_isMuted = muted;
	}
	
	private function sendEvent(eventName:String):void {
		// calculate this to mimic HTML5
		_bufferedTime = _bytesLoaded / _bytesTotal * _duration;
		JavascriptTrace.debug(eventName + " - buffered time: " + _bufferedTime + ", current time: " + currentTime());

		// build JSON
		var values:String =
			"duration:" + _duration +
			",framerate:" + _framerate +
			",currentTime:" + currentTime() +
			",muted:" + _isMuted +
			",paused:" + _isPaused +
			",ended:" + _isEnded +
			",volume:" + _volume +
			",src:\"" + _currentUrl + "\"" +
			",bytesTotal:" + _bytesTotal +
			",bufferedBytes:" + _bytesLoaded +
			",bufferedTime:" + _bufferedTime +
			",videoWidth:" + _videoWidth +
			",videoHeight:" + _videoHeight +
			"";

		_javascriptInterface.sendEvent(eventName, values);
	}
	
	private function parseRTMP(url:String):Object {
		var match:Array = url.match(/(.*)\/((flv|mp4|mp3):.*)/);
		var rtmpInfo:Object = {
			server: null,
			stream: null
		};

		if (match) {
			rtmpInfo.server = match[1];
			rtmpInfo.stream = match[2];
		}
		else {
			rtmpInfo.server = url.replace(/\/[^\/]+$/,"/");
			rtmpInfo.stream = url.split("/").pop();
		}

		JavascriptTrace.debug("parseRTMP - server: " + rtmpInfo.server + " stream: " + rtmpInfo.stream);

		return rtmpInfo;
	}
	
	private function getCurrentUrl(pos:Number):String {
	    var url:String = _currentUrl;
	    if (_pseudoStreamingEnabled) {
			if (url.indexOf('?') > -1) {
				url = url + '&' + _pseudoStreamingStartQueryParam + '=' + pos;
			}
			else {
				url = url + '?' + _pseudoStreamingStartQueryParam + '=' + pos;
			}
	    }
	    return url;
	}
}

}
