//used to store and cache set, map setn commands


NodeMap {
	var <>settings;
	var <bundle, <upToDate=false;
	
	*new {
		^super.new.clear
	}
	
	controlClass {
		^NodeMapSetting
	}
	
	map { arg ... args;
		forBy(0, args.size-1, 2, { arg i;
			this.at(args.at(i)).bus_(args.at(i+1));
		});
		upToDate = false;
	}
	
	unmap { arg ... keys;
		keys.do({ arg key;
			var setting;
			setting = settings.at(key);
			if(setting.notNil, {
				setting.bus_(nil);
				if(setting.isEmpty, { settings.removeAt(key) })
			});
		});
		upToDate = false;
		
	}
	
	setn { arg ... args;
		forBy(0, args.size-1, 2, { arg i;
			this.at(args.at(i)).value_(args.at(i+1).asCollection);
		});
		upToDate = false;
	}
	
	set { arg ... args;
		forBy(0, args.size-1, 2, { arg i;
			this.at(args.at(i)).value_(args.at(i+1));
		});
		upToDate = false;
		
	}
	
	unset { arg ... keys;
		keys.do({ arg key;
			var s;
			s = settings.at(key);
			if(s.notNil, {
				s.value_(nil);
				if(s.isEmpty, { settings.removeAt(key) })
			})
		});
		upToDate = false;
	}
	
	send { arg server, nodeID, latency;
		var bundle;
		bundle = List.new;
		this.addToBundle(bundle, nodeID);
		server.listSendBundle(latency, bundle);
	}
	
	sendToNode { arg node, latency;
		node = node.asTarget;
		this.send(node.server, node.nodeID, latency)
	}
	
	clear {
		settings = IdentityDictionary.new;
	}
	
	
	at { arg key;
		var setting;
		setting = settings.at(key);
		if(setting.isNil, { 
			setting = this.controlClass.new(key); 
			settings.put(key, setting) 
		});
		^setting
	}
	
	valueAt { arg key;
		^settings.at(key).value
	}
	
	emptyBundle { ^#[[15, nil],[16, nil], [14, nil]].copy } //set, setn, map
	
	updateBundle { arg nodeID;
			
			if(upToDate.not, {
				bundle = this.emptyBundle;
				settings.do({ arg item; item.addToBundle(bundle) });
				bundle = bundle.reject({ arg item; item.size == 2 }); //remove unused
				upToDate = true;
				[bundle, \madeNewBundle].debug;
			});
			
			bundle.do({ arg item;
					item.put(1, nodeID); //the nodeID is always second in a synth message
			});
	}
	
	
	addToBundle { arg inBundle, target;
			target = target.asNodeID;
			this.updateBundle(target);
			inBundle.addAll(bundle);
	}
	
	copy {
		var res, nset;
		res = this.class.new;
		nset = res.settings; 
		settings.keysValuesDo({ arg key, val; nset.put(key, val.copy) });
		^res
	}
	

}


ProxyNodeMap : NodeMap {

		var <>parents, <>proxy;
		
		clear {
			super.clear;
			parents = IdentityDictionary.new;
		}
		
		controlClass {
			^ProxyNodeMapSetting
		}
		
		wakeUpParentsToBundle { arg bundle, checkedAlready;
			parents.do({ arg item; item.wakeUpToBundle(bundle, checkedAlready) });
		}
		
		lag { arg args;
			forBy(0, args.size-1, 2, { arg i;
				this.at(args.at(i)).lag_(args.at(i+1));
			});
		}
		unlag { arg args;
			args.do({ arg key;
				var s;
				s = settings.at(key); 
				if(s.notNil, { 
					s.lag_(nil); 
					if(s.isEmpty, { settings.removeAt(key) })
				});
			});
		}
		
		lagsFor { arg keys;
			^keys.collect({ arg key;
				var res;
				res = settings.at(key);
				if(res.notNil, { res.lag }, { nil })
			})
		}
				
		mappingKeys {
			^settings.select({ arg item; item.bus.notNil }).collect({ arg item; item.key })
		}
						
		map { arg ... args;
			var mapArgs, playing;
			mapArgs = [];
			playing = proxy.isPlaying;
			(args.size div: 2).do({ arg i;
				var key, mapProxy, bus, ok;
				key = args.at(i*2).asArray;
				mapProxy = args.at(2*i+1);
				ok = mapProxy.initBus(\control, key.size);
				if(ok, {
					if(playing && mapProxy.isPlaying.not, { mapProxy.wakeUp;  });
					min(key.size, mapProxy.numChannels ? 1).do({ arg chan;
						var theKey;
						theKey = key.at(chan);
						this.at(theKey).bus_(mapProxy).channelOffset_(chan);
						parents = parents.put(theKey, mapProxy);
					});
				}, {
					"rate / numChannels doesn't match".inform
				});
			});
			upToDate = false;
		}
		
		mapEnvir { arg keys;
			var args;
			keys = keys ? settings.keys;
			args = Array.new(keys.size*2);
			keys.do({ arg key; args.add(key); args.add(currentEnvironment.at(key)) });
			this.map(args);
		}
		
		unmap { arg ... keys;
			var setting;
			if(keys.at(0).isNil, { keys = this.mappingKeys });
			keys.do({ arg key;
				setting = settings.at(key);
				if(setting.notNil, {
					setting.bus_(nil);
					parents.removeAt(key);
					if(setting.isEmpty, { settings.removeAt(key) })
				});
			});
			upToDate = false;
		}

	
}


