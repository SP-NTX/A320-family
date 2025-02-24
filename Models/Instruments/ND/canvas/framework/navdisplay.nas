# A3XX ND Canvas
# Joshua Davidson (Octal450)
# Based on work by artix

# Copyright (c) 2023 Josh Davidson (Octal450)

# Override FGDATA/Nasal/canvas/map/navdisplay.mfd

var default_hash = canvas.default_hash;
var _MP_dbg_lvl = canvas._MP_dbg_lvl;
var assert_m = canvas.assert_m;

var wxr_live_tree = "/instrumentation/wxr";
var adirs_3 = props.globals.getNode("/instrumentation/efis[0]/nd/ir-3", 1);

var easeArrow = {
	new: func(elem) {
		var m = {parents: [easeArrow]};
		m.req_rot_rad = 0;
		m.req_rot_deg = 0;
		m.last_rot_deg = nil;
		m.last_rot_rad = 0;
		m.element = elem;
		m.time = 0;
		m.duration = 0;
		m.startval = 0;
		m.diffval = 0;
		m.nav = "";
		m.mhz = 0;
		m.changed = 1;
		return m;
	},
	setVisible: func(v) {
		if (v == 1 and me.last_rot_deg == nil) me.setzero();
		me.element.setVisible(v);
	},
	hide: func {
		me.element.hide();
	},
	reset: func {			
		#me.element.hide();
		me.duration = 0;
		me.changed = 1;		
	},
	setzero: func {
		me.duration = 0;
		me.last_rot_deg = 360 - getprop("orientation/heading-deg");
		me.last_rot_rad = me.last_rot_deg * D2R;
		me.req_rot_rad = me.last_rot_rad;
		me.element.setRotation(me.last_rot_rad);
	},
	listen: func (path) {
		me.nav = path ~ "/frequencies/selected-mhz";
		setlistener(me.nav, func {
			var freq = getprop(me.nav);
			if (me.mhz != freq) {				
				me.mhz = freq;
				me.reset();
			}
		});		
	},
	setRotation: func(rad)  {			
		var deg = 0;
		var gap = 0;
		if (me.last_rot_deg == nil) me.setzero();
		rad = math.round(rad * 1000)  / 1000;
		gap = math.abs(rad - me.req_rot_rad);
		#if (gap>=180*D2R) gap = 360*D2R - gap;
		if (gap>0.0009) {
			#print("VOR rotation");			
			#else if (me.duration>0) gap = math.abs(rad - me.last_rot_rad);
			deg = rad * 57.29578;
			#me.duration = 0;
			if (me.duration > 0) {
				var add = deg - me.req_rot_deg;
				if (add>=180) add = add - 360;
				me.diffval += add;
				me.duration = math.abs( math.round(me.diffval * 0.19) );  # rad 36/3
			}
			else if (me.changed == 1) {				
				#if (me.last_rot_deg == nil) me.reset();
				me.startval = me.last_rot_deg;
				me.diffval = deg - me.last_rot_deg;
				while (me.diffval<0) me.diffval += 360;				
				if (me.changed == 1 and me.diffval < 180) me.diffval += 360;
				#print("VOR animation:" ~ me.diffval);
				#me.time = 0;
				me.duration = math.abs( math.round(me.diffval * 0.19) );  # rad 36/3
			} else {
				me.duration = 0;
			}
			if (me.duration < 2) {
				me.last_rot_rad = rad;
				me.last_rot_deg = deg;
				me.element.setRotation(rad);
				me.duration = 0;
				me.time = 0;
				me.changed = 0;
			}
			me.req_rot_rad = rad;
			me.req_rot_deg = deg;
		}
		if (me.duration > 0) {
			var tx = me.time / me.duration;
			if (tx>1) tx = 1;
			#thanks to https://easings.net/#easeOutCubic
			deg = (1 - math.pow(1 - tx, 3)) * me.diffval + me.startval;
			deg = math.mod(deg,360);				
			#print("DEG: " ~ deg);
			me.element.setRotation(deg * D2R);
			me.time += 1;
			if (tx>=1) {
				me.duration = 0;
				me.time = 0;
				me.changed = 0;
				me.last_rot_deg = deg;
				me.last_rot_rad = rad;
			}
		}

	}
};

var symbolDistNM = {
	new: func(name, nd) {
		var m = {parents: [symbolDistNM] };
		m.group = nd.getElementById(name);
		m.expn = nd.getElementById(name ~ "1");
		m.mant = nd.getElementById(name ~ "2");
		return m;
	},
	hide: func {
		me.group.hide();
	},
	show: func {
		me.group.show();
	},
	setText: func(txt) {
		var parts = ( txt != "" ) ? split( "." , txt ) : nil;
		if ( parts != nil and size(parts) == 2 ) {
			me.expn.setText(parts[0]);
			me.mant.setText("." ~ parts[1]);
		} else {
			me.expn.setText(txt);
			me.mant.setText("");
		}
	},
	setColor: func(r,g,b) {
		me.expn.setColor(r,g,b);
		me.mant.setColor(r,g,b);
	},
	setFloat: func(val) {
		var parts = split( "." , sprintf("%03.1f",val) );
		me.expn.setText(parts[0]);
		me.mant.setText("." ~ parts[1]);
	}
};

canvas.NavDisplay.set_switch = func(s, v) {
	var switch = me.efis_switches[s];
	if(switch == nil) return nil;
	var path = me.efis_path ~ switch.path ;
	#print(s,":Getting switch prop:", path);

	setprop( path, v );
};

canvas.NavDisplay.get_nav_path = func (type, idx) {
	var name = (type == "dme" ? type : "nav");
	var path = "instrumentation/%s[%d]/";
	var indexes = me.radio_cfg[type];
	if (indexes != nil) {
		idx = indexes[idx];
	}
	return sprintf(path, name, idx);
};

canvas.NavDisplay.newMFD = func(canvas_group, parent=nil, nd_options=nil, update_time=0.05) {
	if (me.inited) die("MFD already was added to scene");
	me.range_dependant_layers = [];
	me.always_update_layers = {};
	me.inited = 1;
	me.nd = canvas_group;
	me.canvas_handle = parent;
	me.df_options = nil;
	if(contains(me.nd_style, "options"))
		me.df_options = me.nd_style.options;
	nd_options = default_hash(nd_options, me.df_options);
	me.options = nd_options;
	me.route_driver = nil;
	if(contains(me.options, "route_driver")){
		me.route_driver = me.options.route_driver;
	}
	elsif(contains(me.options, "defaults")){
		if(contains(me.options.defaults, "route_driver"))
			me.route_driver = me.options.defaults.route_driver;
	}
	me.radio_cfg = me.options["radio"];
	if (me.radio_cfg == nil) me.radio_cfg = {};

	# load the specified SVG file into the me.nd group and populate all sub groups

	canvas.parsesvg(me.nd, me.nd_style.svg_filename, {"font-mapper": me.nd_style.font_mapper});
	me.symbols = {}; # storage for SVG elements, to avoid namespace pollution (all SVG elements end up  here)

	foreach(var feature; me.nd_style.features ) {
		me.symbols[feature.id] = me.nd.getElementById(feature.id).updateCenter();
		if(contains(feature.impl,"init")) feature.impl.init(me.nd, feature); # call The element"s init code (i.e. updateCenter)
	}

	### this is the "old" method that"s less flexible, we want to use the style hash instead (see above)
	# because things are much better configurable that way
	# now look up all required SVG elements and initialize member fields using the same name  to have a convenient handle
	foreach(var element; ["dmeL","dmeR","vorL","vorR","vorLId","vorRId",
			"status.wxr","status.wpt","status.sta","status.arpt","terrHI","terrLO","TerrLabel","terrAhead","terrAltGroup",
			"vorLIdtuneMode","vorRIdtuneMode"])
	me.symbols[element] = me.nd.getElementById(element);

	foreach(var element; ["dmeLDist","dmeRDist"])
	me.symbols[element] = symbolDistNM.new( element, me.nd );

	me.symbols.dmeLDist.setColor(0.195,0.96,0.097);
	me.symbols.dmeRDist.setColor(0.195,0.96,0.097);

	# load elements from vector image, and create instance variables using identical names, and call updateCenter() on each
	# anything that needs updatecenter called, should be added to the vector here
	#
	foreach(var element; ["staFromL2","staToL2","staFromR2","staToR2",
			"hdgTrk","hdgBug","HdgBugCRT","TrkBugLCD","HdgBugLCD","curHdgPtr",
			"HdgBugCRT2","TrkBugLCD2","HdgBugLCD2","hdgBug2","selHdgLine","selHdgLine2","curHdgPtr2",
			"staToL","staFromL","staToR","staFromR"] )
	me.symbols[element] = me.nd.getElementById(element).updateCenter();

	foreach(var element; ["staArrowL2","staArrowR2","staArrowL","staArrowR"] )
	me.symbols[element] = easeArrow.new( me.nd.getElementById(element).updateCenter() );

	me.map = me.nd.createChild("map","map")
	.set("clip", "rect(124, 1024, 1024, 0)")
	.set("screen-range", 700)
	.set("z-index",-1);

	me.compassHdgTrk = 0; # last compass rotation deg

	me.update_sub(); # init some map properties based on switches

	var vor1_path = "/instrumentation/nav[2]";
	var vor2_path = "/instrumentation/nav[3]";
	# predicate for the draw controller
	var is_tuned = func(freq) {
		var nav1=getprop(vor1_path~ "frequencies/selected-mhz");
		var nav2=getprop(vor1_path~ "frequencies/selected-mhz");
		if (freq == nav1 or freq == nav2) return 1;
		return 0;
	}

	# listen for (VOR) NAV frequency change
	me.symbols.staArrowL.listen(vor1_path);
	me.symbols.staArrowL2.listen(vor1_path);
	me.symbols.staArrowR.listen(vor2_path);
	me.symbols.staArrowR2.listen(vor2_path);

	# another predicate for the draw controller
	var get_course_by_freq = func(freq) {
		if (freq == getprop(vor1_path~ "frequencies/selected-mhz"))
			return getprop(vor1_path~ "radials/selected-deg");
		else
			return getprop(vor2_path~ "radials/selected-deg");
	}

	var get_current_position = func {
		delete(caller(0)[0], "me"); # remove local me, inherit outer one
		return [
			me.aircraft_source.get_lat(), me.aircraft_source.get_lon()
		];
	}

	# a hash with controller callbacks, will be passed onto draw routines to customize behavior/appearance
	# the point being that draw routines don"t know anything about their frontends (instrument or GUI dialog)
	# so we need some simple way to communicate between frontend<->backend until we have real controllers
	# for now, a single controller hash is shared by most layers - unsupported callbacks are simply ignored by the draw files
	#

	var controller = {
		parents: [canvas.Map.Controller],
		_pos: nil, _time: nil,
		is_tuned:is_tuned,
		get_tuned_course:get_course_by_freq,
		get_position: get_current_position,
		new: func(map) return { parents:[controller], map:map },
		should_update_all: func {
			# TODO: this is just copied from aircraftpos.controller,
			# it really should be moved to somewhere common and reused
			# and extended to fully differentiate between "static"
			# and "volatile" layers.
			var pos = me.map.getPosCoord();
			if (pos == nil) return 0;
			var time = systime();
			if (me._pos == nil)
				me._pos = geo.Coord.new(pos);
			else {
				var dist_m = me._pos.direct_distance_to(pos);
				# 2 NM until we update again
				if (dist_m < 2 * NM2M) return 0;
				# Update at most every 4 seconds to avoid excessive stutter:
				elsif (time - me._time < 4) return 0;
			}
			#print("update aircraft position");
			var (x,y,z) = pos.xyz();
			me._pos.set_xyz(x,y,z);
			me._time = time;
			return 1;
		},
	};
	me.map.setController(controller);

	###
	# set up various layers, controlled via callbacks in the controller hash
	# revisit this code once Philosopher"s "Smart MVC Symbols/Layers" work is committed and integrated

	# helper / closure generator
	var make_event_handler = func(predicate, layer) func predicate(me, layer);

	me.layers={}; # storage container for all ND specific layers
	me.predicates={};
	# look up all required layers as specified per the NDStyle hash and do the initial setup for event handling
	var default_opts = me.options != nil and contains(me.options, "defaults") ? me.options.defaults : nil;
	foreach(var layer; me.nd_style.layers) {
		if(layer["disabled"]) continue; # skip this layer
		#print("newMFD(): Setting up ND layer:", layer.name);

		var the_layer = nil;
		if(!layer["isMapStructure"]) # set up an old INEFFICIENT and SLOW layer
			the_layer = me.layers[layer.name] = canvas.MAP_LAYERS[layer.name].new( me.map, layer.name, controller );
		else {
			logprint(_MP_dbg_lvl, "Setting up MapStructure-based layer for ND, name:", layer.name);
			var opt = me.options != nil and me.options[layer.name] != nil ? me.options[layer.name] :nil;
			if(opt == nil and contains(layer, "options"))
				opt = layer.options;
			if(opt != nil and default_opts != nil)
				opt = default_hash(opt, default_opts);
			#elsif(default_opts != nil)
			#    opt = default_opts;
			var style = nil;
			if(contains(layer, "style"))
				style = layer.style;
			#print("Options is: ", opt!=nil?"enabled":"disabled");
			#debug.dump(opt);
			me.map.addLayer(
				factory: canvas.SymbolLayer,
				type_arg: layer.name,
				opts: opt,
				visible:0,
				style: style,
				priority: layer["z-index"]
			);
			#me.map.addLayer(canvas.SymbolLayer, layer.name, layer["z-index"], style, opt, 0);
			the_layer = me.layers[layer.name] = me.map.getLayer(layer.name);
			if(opt != nil and contains(opt, "range_dependant")){
				if(opt.range_dependant)
					append(me.range_dependant_layers, the_layer);
			}
			if(contains(layer, "always_update"))
				me.always_update_layers[layer.name] = layer.always_update;
			if (1) (func {
				var l = layer;
				var _predicate = l.predicate;
				l.predicate = func {
					var t = systime();
					call(_predicate, arg, me);
					logprint(_MP_dbg_lvl, "Took "~((systime()-t)*1000)~"ms to update layer "~l.name);
				}
			})();
		}

		# now register all layer specific notification listeners and their corresponding update predicate/callback
		# pass the ND instance and the layer handle to the predicate when it is called
		# so that it can directly access the ND instance and its own layer (without having to know the layer"s name)
		var event_handler = make_event_handler(layer.predicate, the_layer);
		me.predicates[layer.name] = event_handler;
		foreach(var event; layer.update_on) {
			# this handles timers
			if (typeof(event)=="hash" and contains(event, "rate_hz")) {
				#print("FIXME: navdisplay.mfd timer handling is broken ATM");
				var job=me.addtimer(1/event.rate_hz, event_handler);
				job.start();
			}
			# and this listeners
			else
				# print("Setting up subscription:", event, " for ", layer.name, " handler id:", id(event_handler) );
				me.listen_switch(event, event_handler);
		} # foreach event subscription
		# and now update/init each layer once by calling its update predicate for initialization
		event_handler();
	} # foreach layer

	me.mapCamera = traffic.Camera.new({
		range: 20,
		screenRange: 436.8545,
		screenCX: 512,
		screenCY: 512,
	});
	me.trafficGroup = me.nd.createChild("group");
	me.trafficLayer = traffic.TrafficLayer.new(me.mapCamera, me.trafficGroup);
	me.trafficLayer.start();
	me.trafficGroup.set("z-index", -1);
	
	#print("navdisplay.mfd:ND layer setup completed");

	# TODO: move this to RTE.lcontroller ?
	me.listen("/autopilot/route-manager/current-wp", func(activeWp) {
		canvas.updatewp( activeWp.getValue() );
	});

};

canvas.NavDisplay.update_sub = func(){
	# Variables:
	var userLat = me.aircraft_source.get_lat();
	var userLon = me.aircraft_source.get_lon();
	var userGndSpd = me.aircraft_source.get_gnd_spd();
	var userVSpd = me.aircraft_source.get_vspd();
	var dispLCD = me.get_switch("toggle_display_type") == "LCD";
	# Heading update
	var userHdgMag = me.aircraft_source.get_hdg_mag();
	var userHdgTru = me.aircraft_source.get_hdg_tru();
	var userTrkMag = me.aircraft_source.get_trk_mag();
	var userTrkTru = me.aircraft_source.get_trk_tru();

	if(me.get_switch("toggle_true_north")) {
		var userHdg=userHdgTru;
		me.userHdg=userHdgTru;
		var userTrk=userTrkTru;
		me.userTrk=userTrkTru;
	} else {
		var userHdg=userHdgMag;
		me.userHdg=userHdgMag;
		var userTrk=userTrkMag;
		me.userTrk=userTrkMag;
	}
	# this should only ever happen when testing the experimental AI/MP ND driver hash (not critical)
	# or when an error occurs (critical)
	if (!userHdg or !userTrk or !userLat or !userLon) {
		print("aircraft source invalid, returning !");
		return;
	}
	if (me.aircraft_source.get_gnd_spd() < 80) {
		userTrk = userHdg;
		me.userTrk=userHdg;
	}

	var reqHdg = 0;

	if((me.in_mode("toggle_display_mode", ["MAP"]) and me.get_switch("toggle_display_type") == "CRT")
	   or (me.get_switch("toggle_track_heading") and me.get_switch("toggle_display_type") == "LCD")) {
		userHdgTrk = userTrk;
		me.userHdgTrk = userTrk;
		me.compassHdgTrk = userTrk;
		userHdgTrkTru = userTrkTru;
		me.symbols.hdgTrk.setText("TRK");
	} else {
		if (userHdg != me.compassHdgTrk) {
			var dist = userHdg - me.compassHdgTrk;
			if (dist>180) dist = dist - 360;
			elsif (dist<-180) dist = 360 + dist;
			if (dist>0) {
				dist = dist * 0.3;
				if (dist>10) dist = 10;
				me.compassHdgTrk = (dist<0.1) ? userHdg : math.mod(me.compassHdgTrk+dist,360);
			} 
			elsif (dist<0) {
				dist = dist * 0.3;
				if (dist<-10) dist = -10;
				me.compassHdgTrk = (dist>-0.1) ? userHdg : math.mod(me.compassHdgTrk+dist,360);
			}						
		}
		userHdgTrk = me.compassHdgTrk;
		me.userHdgTrk = me.compassHdgTrk;
		userHdgTrkTru = userHdgTru;
		me.symbols.hdgTrk.setText("HDG");
	}


	# First, update the display position of the map
	var oldRange = me.map.getRange();
	var pos = {
		lat: nil, lon: nil,
		alt: nil, hdg: nil,
		range: nil,
	};
	# reposition the map, change heading & range:
	var pln_wpt_idx = getprop(me.efis_path ~ "/inputs/plan-wpt-index");
	if(me.in_mode("toggle_display_mode", ["PLAN"]) and pln_wpt_idx >= 0) {
		if(me.route_driver != nil){
			var wp = me.route_driver.getPlanModeWP(pln_wpt_idx);
			if(wp != nil){
				pos.lat = wp.wp_lat;
				pos.lon = wp.wp_lon;
			} else {
				pos.lat = getprop("autopilot/route-manager/route/wp["~pln_wpt_idx~"]/latitude-deg");
				pos.lon = getprop("autopilot/route-manager/route/wp["~pln_wpt_idx~"]/longitude-deg");
			}
		} else {
			pos.lat = getprop("autopilot/route-manager/route/wp["~pln_wpt_idx~"]/latitude-deg");
			pos.lon = getprop("autopilot/route-manager/route/wp["~pln_wpt_idx~"]/longitude-deg");
		}
	} else {
		pos.lat = userLat;
		pos.lon = userLon;
	}
	if(me.in_mode("toggle_display_mode", ["PLAN"])) {
		pos.hdg = 0;
		pos.range = me.rangeNm()*2
	} else {
		pos.range = me.rangeNm(); # avoid this  here, use a listener instead
		pos.hdg = userHdgTrkTru;
	}
	if(me.options != nil and (var pos_callback = me.options["position_callback"]) != nil)
		pos_callback(me, pos);
	call(me.map.setPos, [pos.lat, pos.lon], me.map, pos);
	if(pos.range != oldRange){
		foreach(l; me.range_dependant_layers){
			l.update();
		}
	}
};

canvas.NavDisplay.update = func() # FIXME: This stuff is still too aircraft specific, cannot easily be reused by other aircraft
{
	var _time = systime();
	# Disables WXR Live if it's not enabled. The toggle_weather_live should be common to all 
	# ND instances.
	var wxr_live_enabled = getprop(wxr_live_tree~'/enabled');
	if(wxr_live_enabled == nil or wxr_live_enabled == '') 
		wxr_live_enabled = 0;
	me.set_switch('toggle_weather_live', wxr_live_enabled);
	call(me.update_sub, nil, nil, caller(0)[0]); # call this in the same namespace to "steal" its variables

	# MapStructure update!
	if (me.map.controller.should_update_all()) {
		me.map.update();
	} else {
		# TODO: ugly list here
		# FIXME: use a VOLATILE layer helper here that handles TFC, APS, WXR etc ?
		var update_layers = me.always_update_layers;
		me.map.update(func(layer) contains(update_layers, layer.type));
	}

	# Other symbol update
	# TODO: should be refactored!
	var translation_callback = nil;
	if(me.options != nil)
		translation_callback = me.options["translation_callback"];
	if(typeof(translation_callback) == "func"){
		var trsl = translation_callback(me);
		me.map.setTranslation(trsl.x, trsl.y);
	} else {
		if(me.in_mode("toggle_display_mode", ["PLAN"]))
			me.map.setTranslation(512,512);
		elsif(me.get_switch("toggle_centered"))
		me.map.setTranslation(512,565);
		else
			me.map.setTranslation(512,824);
	}
	me.mapCamera.repositon(geo.aircraft_position(), me.aircraft_source.get_hdg_tru());
	me.pos = props.globals.getNode("position");
	me.trafficLayer.setRefAlt(me.pos.getValue("altitude-ft"));
	if (me.trafficGroup.getVisible()) {
		me.trafficLayer.update();
		me.trafficLayer.redraw();
	}
	var vor1_path = "/instrumentation/nav[2]";
	var vor2_path = "/instrumentation/nav[3]";
	var dme1_path = "/instrumentation/dme[2]";
	var dme2_path = "/instrumentation/dme[3]";

	
	if(me.get_switch("toggle_lh_vor_adf") == 1) {
		if (fmgc.FMGCInternal.VOR1.freqSet) {
			me.symbols.vorLIdtuneMode.show();
		} else {
			me.symbols.vorLIdtuneMode.hide();
		}
	} else if(me.get_switch("toggle_lh_vor_adf") == -1) {
		if (fmgc.FMGCInternal.ADF1.freqSet) {
			me.symbols.vorLIdtuneMode.show();
		} else {
			me.symbols.vorLIdtuneMode.hide();
		}
	} else {
		me.symbols.vorLIdtuneMode.hide();
	}
	
	if(me.get_switch("toggle_rh_vor_adf") == 1) {
		
		if (fmgc.FMGCInternal.VOR2.freqSet) {
			me.symbols.vorRIdtuneMode.show();
		} else {
			me.symbols.vorRIdtuneMode.hide();
		}
		
		me.symbols.vorR.setText("VOR R");
		me.symbols.vorR.setColor(0.195,0.96,0.097);
		me.symbols.dmeR.setText("DME");
		me.symbols.dmeR.setColor(0.195,0.96,0.097);
		if(getprop(vor2_path~ "in-range"))
			me.symbols.vorRId.setText(getprop(vor2_path~ "nav-id"));
		else
			me.symbols.vorRId.setText(getprop(vor2_path~ "frequencies/selected-mhz-fmt"));
		me.symbols.vorRId.setColor(0.195,0.96,0.097);
		if(getprop(dme2_path~ "in-range"))
			me.symbols.dmeRDist.setText(sprintf("%3.1f",getprop(dme2_path~ "indicated-distance-nm")));
		else me.symbols.dmeRDist.setText(" ---");
			me.symbols.dmeRDist.setColor(0.195,0.96,0.097);
	} elsif(me.get_switch("toggle_rh_vor_adf") == -1) {
	
		if (fmgc.FMGCInternal.ADF2.freqSet) {
			me.symbols.vorRIdtuneMode.show();
		} else {
			me.symbols.vorRIdtuneMode.hide();
		}
		
		me.symbols.vorR.setText("ADF R");
		me.symbols.vorR.setColor(0,0.6,0.85);
		me.symbols.dmeR.setText("");
		me.symbols.dmeR.setColor(0,0.6,0.85);
		if((var navident=getprop("/instrumentation/adf[1]/ident")) != "")
			me.symbols.vorRId.setText(navident);
		else me.symbols.vorRId.setText(sprintf("%3d",pts.Instrumentation.Adf.Frequencies.selectedKhz[1].getValue()));
			me.symbols.vorRId.setColor(0,0.6,0.85);
		me.symbols.dmeRDist.setText("");
		me.symbols.dmeRDist.setColor(0,0.6,0.85);
	} else {
		me.symbols.vorRIdtuneMode.hide();
		me.symbols.vorR.setText("");
		me.symbols.dmeR.setText("");
		me.symbols.vorRId.setText("");
		me.symbols.dmeRDist.setText("");
	}

	# Hide heading bug 45 secs after change
	var vhdg_bug = fmgc.Input.hdg.getValue();
	var hdg_bug_active = fmgc.Custom.showHdg.getBoolValue();

	if((me.in_mode("toggle_display_mode", ["MAP"]) and me.get_switch("toggle_display_type") == "CRT")
	   or (me.get_switch("toggle_track_heading") and me.get_switch("toggle_display_type") == "LCD"))
	{
		me.symbols.curHdgPtr.setRotation((userHdg-userTrk)*D2R);
		me.symbols.curHdgPtr2.setRotation((userHdg-userTrk)*D2R);
	}
	else
	{
		me.symbols.curHdgPtr.setRotation(0);
		me.symbols.curHdgPtr2.setRotation(0);
	}
	if(!me.in_mode("toggle_display_mode", ["PLAN"])) {
		var hdgBugRot = (vhdg_bug-userHdgTrk)*D2R;
		me.symbols.selHdgLine.setRotation(hdgBugRot);
		me.symbols.hdgBug.setRotation(hdgBugRot);
		me.symbols.hdgBug2.setRotation(hdgBugRot);
		me.symbols.selHdgLine2.setRotation(hdgBugRot);
	}

	var staPtrVis = (!me.in_mode("toggle_display_mode", ["PLAN"]) and  (me.adirs_property.getValue() == 1 or (adirs_3.getValue() == 1 and att_switch.getValue() == me.attitude_heading_setting)));
	if((me.in_mode("toggle_display_mode", ["MAP"]) and me.get_switch("toggle_display_type") == "CRT")
	   or (me.get_switch("toggle_track_heading") and me.get_switch("toggle_display_type") == "LCD"))
	{
		var vorheading = userTrkTru;
		var adfheading = userTrkMag;
	}
	else
	{
		var vorheading = userHdgTru;
		var adfheading = userHdgMag;
	}
	if (getprop("/instrumentation/nav[2]/heading-deg") != nil) {
		var nav0hdg = getprop("/instrumentation/nav[2]/heading-deg") - getprop("orientation/heading-deg");
	} else {
		var nav0hdg = 0;
	}
	if (getprop("/instrumentation/nav[3]/heading-deg") != nil) {
		var nav1hdg = getprop("/instrumentation/nav[3]/heading-deg") - getprop("orientation/heading-deg");
	} else {
		var nav1hdg = 0;
	}
	var adf0hdg = getprop("/instrumentation/adf/indicated-bearing-deg");
	var adf1hdg = getprop("/instrumentation/adf[1]/indicated-bearing-deg");
	if(!me.get_switch("toggle_centered")) {
		if((getprop("/instrumentation/nav[2]/in-range") and me.get_switch("toggle_lh_vor_adf") == 1)) {
			me.symbols.staToL.setColor(0.195,0.96,0.097);
			me.symbols.staFromL.setColor(0.195,0.96,0.097);
			me.symbols.staArrowL.setRotation(nav0hdg*D2R);
			me.symbols.staArrowL.setVisible(staPtrVis);
		}
		elsif(getprop("/instrumentation/adf/in-range") and (me.get_switch("toggle_lh_vor_adf") == -1)) {
			me.symbols.staToL.setColor(0,0.6,0.85);
			me.symbols.staFromL.setColor(0,0.6,0.85);
			me.symbols.staArrowL.setRotation(adf0hdg*D2R);
			me.symbols.staArrowL.setVisible(staPtrVis);
		} else {
			me.symbols.staArrowL.hide();
		}
		if((getprop("/instrumentation/nav[3]/in-range") and me.get_switch("toggle_rh_vor_adf") == 1)) {
			me.symbols.staToR.setColor(0.195,0.96,0.097);
			me.symbols.staFromR.setColor(0.195,0.96,0.097);
			me.symbols.staArrowR.setRotation(nav1hdg*D2R);
			me.symbols.staArrowR.setVisible(staPtrVis);
		} elsif(getprop("/instrumentation/adf[1]/in-range") and (me.get_switch("toggle_rh_vor_adf") == -1)) {
			me.symbols.staToR.setColor(0,0.6,0.85);
			me.symbols.staFromR.setColor(0,0.6,0.85);
			me.symbols.staArrowR.setRotation(adf1hdg*D2R);
			me.symbols.staArrowR.setVisible(staPtrVis);
		} else {
			me.symbols.staArrowR.hide();
		}
		me.symbols.staArrowL2.hide();
		me.symbols.staArrowR2.hide();
		me.symbols.curHdgPtr2.hide();
		me.symbols.HdgBugCRT2.hide();
		me.symbols.TrkBugLCD2.hide();
		me.symbols.HdgBugLCD2.hide();
		me.symbols.selHdgLine2.hide();
		me.symbols.curHdgPtr.setVisible(staPtrVis);
		me.symbols.HdgBugCRT.setVisible(staPtrVis and !dispLCD);
		if (me.get_switch("toggle_track_heading")) {
			me.symbols.HdgBugLCD.hide();
			if (hdg_bug_active) {
				me.symbols.TrkBugLCD.setVisible(staPtrVis and dispLCD);
			} else {
				me.symbols.TrkBugLCD.hide();
			}
		} else {
			me.symbols.TrkBugLCD.hide();
			if (hdg_bug_active) {
				me.symbols.HdgBugLCD.setVisible(staPtrVis and dispLCD);
			} else {
				me.symbols.HdgBugLCD.hide();
			}
		}
		me.symbols.selHdgLine.setVisible(staPtrVis and hdg_bug_active);
	} else {
		if((getprop("/instrumentation/nav[2]/in-range") and me.get_switch("toggle_lh_vor_adf") == 1)) {
			me.symbols.staFromL2.setColor(0.195,0.96,0.097);
			me.symbols.staToL2.setColor(0.195,0.96,0.097);
			me.symbols.staArrowL2.setRotation(nav0hdg*D2R);
			me.symbols.staArrowL2.setVisible(staPtrVis);
		} elsif(getprop("/instrumentation/adf/in-range") and (me.get_switch("toggle_lh_vor_adf") == -1)) {
			me.symbols.staFromL2.setColor(0,0.6,0.85);
			me.symbols.staToL2.setColor(0,0.6,0.85);
			me.symbols.staArrowL2.setRotation(adf0hdg*D2R);
			me.symbols.staArrowL2.setVisible(staPtrVis);
		} else {
			me.symbols.staArrowL2.hide();
		}
		if((getprop("/instrumentation/nav[3]/in-range") and me.get_switch("toggle_rh_vor_adf") == 1)) {
			me.symbols.staFromR2.setColor(0.195,0.96,0.097);
			me.symbols.staToR2.setColor(0.195,0.96,0.097);
			me.symbols.staArrowR2.setRotation(nav1hdg*D2R);
			me.symbols.staArrowR2.setVisible(staPtrVis);
		} elsif(getprop("/instrumentation/adf[1]/in-range") and (me.get_switch("toggle_rh_vor_adf") == -1)) {
			me.symbols.staFromR2.setColor(0,0.6,0.85);
			me.symbols.staToR2.setColor(0,0.6,0.85);
			me.symbols.staArrowR2.setRotation(adf1hdg*D2R);
			me.symbols.staArrowR2.setVisible(staPtrVis);
		} else {
			me.symbols.staArrowR2.hide();
		}
		me.symbols.staArrowL.hide();
		me.symbols.staArrowR.hide();
		me.symbols.curHdgPtr.hide();
		me.symbols.HdgBugCRT.hide();
		me.symbols.TrkBugLCD.hide();
		me.symbols.HdgBugLCD.hide();
		me.symbols.selHdgLine.hide();
		me.symbols.curHdgPtr2.setVisible(staPtrVis);
		me.symbols.HdgBugCRT2.setVisible(staPtrVis and !dispLCD);
		if (me.get_switch("toggle_track_heading")) {
			me.symbols.HdgBugLCD2.hide();
			if (hdg_bug_active) {
				me.symbols.TrkBugLCD2.setVisible(staPtrVis and dispLCD);
			} else {
				me.symbols.TrkBugLCD2.hide();
			}
		} else {
			me.symbols.TrkBugLCD2.hide();
			if (hdg_bug_active) {
				me.symbols.HdgBugLCD2.setVisible(staPtrVis and dispLCD);
			} else {
				me.symbols.HdgBugLCD2.hide();
			}
		}
		me.symbols.selHdgLine2.setVisible(staPtrVis and hdg_bug_active);
	}

	## run all predicates in the NDStyle hash and evaluate their true/false behavior callbacks
	## this is in line with the original design, but normally we don"t need to getprop/poll here,
	## using listeners or timers would be more canvas-friendly whenever possible
	## because running setprop() on any group/canvas element at framerate means that the canvas
	## will be updated at frame rate too - wasteful ... (check the performance monitor!)

	foreach(var feature; me.nd_style.features ) {
		# for stuff that always needs to be updated
		if (contains(feature.impl, "common")) feature.impl.common(me);
		# conditional stuff
		if(!contains(feature.impl, "predicate")) continue; # no conditional stuff
		if ( var result=feature.impl.predicate(me) )
		feature.impl.is_true(me, result); # pass the result to the predicate
		else
			feature.impl.is_false( me, result ); # pass the result to the predicate
	}

	## update the status flags shown on the ND (wxr, wpt, arpt, sta)
	# this could/should be using listeners instead ...
	me.symbols["status.wxr"].setVisible( me.get_switch("toggle_weather") and me.in_mode("toggle_display_mode", ["MAP"]));
	me.symbols["status.wpt"].setVisible( me.get_switch("toggle_waypoints") and me.in_mode("toggle_display_mode", ["MAP"]));
	me.symbols["status.arpt"].setVisible( me.get_switch("toggle_airports") and me.in_mode("toggle_display_mode", ["MAP"]));
	me.symbols["status.sta"].setVisible( me.get_switch("toggle_stations") and  me.in_mode("toggle_display_mode", ["MAP"]));
	# Okay, _how_ do we hook this up with FGPlot?
	logprint(_MP_dbg_lvl, "Total ND update took "~((systime()-_time)*100)~"ms");
	setprop("instrumentation/navdisplay["~ canvas.NavDisplay.id ~"]/update-ms", systime() - _time);
};
