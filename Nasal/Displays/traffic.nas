# Traffic layer
#

var colorByLevel = {
     # 0: other
     0: [0.8,0.8,0.8],
     # 1: proximity
     1: [0.8,0.8,0.8],
     # 2: traffic advisory (TA)
     2: [1,0.75,0],
     # 3: resolution advisory (RA)
     3: [1,0,0],
};

var doFill = {
	0: 0,
	1: 1,
	2: 1,
	3: 1,
};

var colorDefault = [0.8,0.8,0.8];

var drawBlip = func(elem, threatLvl) {
    if (threatLvl == 3) {
        # resolution advisory
        elem.reset()
            .moveTo(-17,-17)
            .horiz(34)
            .vert(34)
            .horiz(-34)
            .close();
    }
    elsif (threatLvl == 2) {
        # traffic advisory
        elem.reset()
            .moveTo(-17,0)
            .arcSmallCW(17,17,0,34,0)
            .arcSmallCW(17,17,0,-34,0);
    }
    elsif (threatLvl == 1) {
        # proximate traffic
        elem.reset()
            .moveTo(-14,0)
            .lineTo(0,-17)
            .lineTo(14,0)
            .lineTo(0,17)
            .close();
    }
    else {
        # other traffic
        elem.reset()
            .moveTo(-14,0)
            .lineTo(0,-17)
            .lineTo(14,0)
            .lineTo(0,17)
            .close();
    }
};


var TrafficLayer = {
    new: func(camera, group) {
        var m = {
            parents: [TrafficLayer],
            camera: camera,
            refAlt: 0,
            group: group,
            items: {},
            sorted: {},
            values: {},
            updateKeys: [],
            addListener: nil,
            delListener: nil,
        };
        return m;
    },

    makeElems: func () {
        if (me.group == nil) return nil;
        var elems = {};
        elems['master'] = me.group.createChild('group');
        elems['blip'] = elems.master.createChild('path')
            .setStrokeLineWidth(0);
        elems['text'] = elems.master.createChild('text')
            .setDrawMode(canvas.Text.TEXT)
            .setText(sprintf("0"))
            .setFont("LiberationFonts/LiberationSans-Regular.ttf")
            .setColor(1,1,1)
            .setFontSize(32)
            .setAlignment("center-center");
        elems['master'].hide();
        elems['arrowUp'] = elems.master.createChild("text")
            .setDrawMode(canvas.Text.TEXT)
            .setText(sprintf("↑"))
            .setFont("LiberationFonts/LiberationSans-Regular.ttf")
            .setColor(1,1,1)
            .setFontSize(50)
            .setTranslation(16, 2)
            .setAlignment("left-center");
        elems['arrowDown'] = elems.master.createChild("text")
            .setDrawMode(canvas.Text.TEXT)
            .setText(sprintf("↓"))
            .setFont("LiberationFonts/LiberationSans-Regular.ttf")
            .setColor(1,1,1)
            .setFontSize(50)
            .setTranslation(16, 2)
            .setAlignment("left-center");
            return elems;
    },

    start: func() {
        me.stop();
        var self = me;
        me.addListener = setlistener('/ai/models/model-added', func(changed, listen, mode, is_child) {
            var path = changed.getValue();
            if (path == nil) return;
            #printf("ADD: %s", path);
            me.values[path] = nil;
            var masterProp = props.globals.getNode(path);
            var prop = {
                'master': masterProp,
            };
            if (me.items[path] == nil) {
                me.items[path] = {
                    prop: prop,
                    elems: me.makeElems(),
                    data: {'threatLevel': -2},
                };
            }
            else {
                me.items[path].prop = prop;
                me.items[path].data = {'threatLevel': -2};
            }            
        }, 1, 1);
        me.delListener = setlistener('/ai/models/model-removed', func(changed, listen, mode, is_child) {
            var path = changed.getValue();
            if (path == nil) return;
            #printf("DEL: %s", path);
            me.values[path] = nil;
            if (me.items[path] == nil) return;
            if (me.items[path] != nil) {
                me.items[path].prop = nil;
                me.items[path].elems.master.hide();
                me.items[path].data = {};
            }
        }, 1, 1);
    },

    stop: func() {
        if (me.addListener != nil) {
            removelistener(me.addListener);
            me.addListener = nil;
        }
        if (me.delListener != nil) {
            removelistener(me.delListener);
            me.delListener = nil;
        }
        me.items = {};
        if (me.group != nil) {
            me.group.removeAllChildren();
        }
    },


    nxtupdatetime: 0,

    update: func() {

        #var _tm = systime();
        #if (me.lastupdatetime != 0) {
        #    if (_tm<me.nxtupdatetime) return;            
        #}
        #me.nxtupdatetime = _tm + 0.25;

        if (size(me.updateKeys) == 0) {
            me.updateKeys = keys(me.items);
        }
        var path = pop(me.updateKeys);
        foreach (var path; keys(me.items)) {
            me.updateItem(path);
        }
    },

    redraw: func() {
        foreach (var path; keys(me.items)) {
            me.redrawItem(me.items[path],me.values[path]);
        }
    },

    setRefAlt: func(alt) {
        me.refAlt = alt;
    },

    proplist: ['lat', 'lon', 'alt', 'threatLevel', 'callsign', 'vspeed', 'tas'],

    updateItem: func(path) {

        var item = me.items[path];
        if (item == nil) return;
        if (item.prop == nil) {
            if (item.elems != nil) {
                item.elems.master.hide();
            }
            return;
        }

        if (item.prop['lat'] == nil) {
            item.prop['lat'] = item.prop.master.getNode('position/latitude-deg');
            item.prop['lon'] = item.prop.master.getNode('position/longitude-deg');
            item.prop['alt'] = item.prop.master.getNode('position/altitude-ft');
        }
        if (item.prop['threatLevel'] == nil) {
            item.prop['threatLevel'] = item.prop.master.getNode('tcas/threat-level');
        }
        if (item.prop['callsign'] == nil) {
            item.prop['callsign'] = item.prop.master.getNode('callsign');
        }
        if (item.prop['vspeed'] == nil) {
            item.prop['vspeed'] = item.prop.master.getNode('velocities/vertical-speed-fps');
            item.prop['tas'] = item.prop.master.getNode('velocities/true-airspeed-kt');
        }

        # this item has a prop associated with it
        if (item.elems == nil) {
            item.elems = me.makeElems();
        }
        var oldThreatLevel = item.data['threatLevel'];
        foreach (var k; me.proplist) {
            if (item.prop[k] != nil) {
                item.data[k] = item.prop[k].getValue();
            }
        }
        if (oldThreatLevel != item.data['threatLevel']) {
            item.data['threatLevelDirty'] = 1;
        }

        var _lat = item.data['lat'];
        var _lon = item.data['lon'];
        var alt = item.data['alt'];
        var vspeed = item.data['vspeed'];
        var tas = item.data['tas'];
        var threatLevelDirty = item.data['threatLevelDirty'];

        me.values[path] = nil;

        if (_lat != nil and _lon != nil and vspeed != nil) {
            
            if (tas<80) { # flying airplane only
                me.values[path] = {visible: 0};
                return; 
            }

            var altDiff100 = ((alt or me.refAlt) - me.refAlt) / 100;

            if (altDiff100 > 99 or altDiff100 < -99) { # check TCAS vertical range
                me.values[path] = {visible: 0};
                return;
            }

            var _val = {visible:1, lat:_lat, lon:_lon};

            var spd = vspeed * 60;
            _val.arrowup = (spd > 500);
            _val.arrowdown = (spd < -500);

            if (math.abs(altDiff100) > 0.5) {
                _val.text = sprintf("%+03d ", altDiff100);
            } else {
                _val.text = "";
            }

            _val.textpy = (altDiff100 <= 0) ? 40 : -30;

            me.values[path] = _val;
            
        }

    },

    redrawItem: func (item,val) {
        #debug.dump("REDRAW ", item.data);

        #var lat = item.data['lat'];
        #var lon = item.data['lon'];
        #var alt = item.data['alt'];
        #var vspeed = item.data['vspeed'];
        #var tas = item.data['tas'];
        #var threatLevelDirty = item.data['threatLevelDirty'];

        if (val != nil and val.visible == 1) {

            var lat = val.lat;
            var lon = val.lon;

            var coords = geo.Coord.new();
            coords.set_latlon(lat, lon);
            var (x, y) = me.camera.project(coords);
            item.elems.master.setTranslation(x, y);
            #printf("%f %f", x, y);
            if (item.data['threatLevelDirty']) {
                #printf('%s THREAT LVL: %i', item.data['callsign'] or '???', item.data['threatLevel']);
                var threatLevel = item.data['threatLevel'];
                #debug.dump(item.data, threatLevel);
                drawBlip(item.elems.blip, threatLevel);
                var rgb = colorByLevel[threatLevel];
                if (rgb == nil) rgb = colorDefault;
                var color = canvas._getColor(rgb);
                var (r, g, b) = rgb;
				item.elems.blip.setColorFill(r, g, b);
				item.elems.text.setColor(r, g, b);
                item.elems.arrowUp.setColor(r, g, b);
                item.elems.arrowDown.setColor(r, g, b);
                item.elems.master.set('z-index', threatLevel + 2);
                item.data['threatLevelDirty'] = 0;
            }

            item.elems.arrowUp.setVisible(val.arrowup);
            item.elems.arrowDown.setVisible(val.arrowdown);

            #item.elems.text.setVisible(math.abs(altDiff100) > 0.5);
            item.elems.text.setText(val.text);
            item.elems.text.setTranslation(0, val.textpy);
            item.elems.master.show();

        } else {

            item.elems.master.hide();

        }
    },

};
