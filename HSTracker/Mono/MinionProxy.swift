//
//  TestInputProxy.swift
//  HSTracker
//
//  Created by Francisco Moraes on 8/11/20.
//  Copyright © 2020 Benjamin Michotte. All rights reserved.
//

import Foundation

class MinionProxy: MonoHandle, MonoClassInitializer {    
    internal static var _class: OpaquePointer?
    
    static var _members = [String: OpaquePointer]()
    
    static func initialize() {
        if MinionProxy._class == nil {
            MinionProxy._class = MonoHelper.loadClass(ns: "BobsBuddy", name: "Minion")
            
            initializeFields(fields: ["minionName", "tier"])
            
            initializeProperties(properties: ["HasWingmen", "baseAttack", "baseHealth", "cleave", "div", "game_id", "golden", "megaWindfury", "poisonous", "reborn", "stealth", "taunt", "vanillaAttack", "vanillaHealth", "windfury"])
        }
    }
    
    required init(obj: UnsafeMutablePointer<MonoObject>?) {
        super.init(obj: obj)
    }

    @MonoPrimitiveProperty(property: "baseAttack", owner: MinionProxy.self)
    var baseAttack: Int32

    @MonoPrimitiveProperty(property: "baseHealth", owner: MinionProxy.self)
    var baseHealth: Int32

    @MonoPrimitiveProperty(property: "taunt", owner: MinionProxy.self)
    var taunt: Bool

    @MonoPrimitiveProperty(property: "div", owner: MinionProxy.self)
    var div: Bool

    @MonoPrimitiveProperty(property: "cleave", owner: MinionProxy.self)
    var cleave: Bool

    @MonoPrimitiveProperty(property: "poisonous", owner: MinionProxy.self)
    var poisonous: Bool

    @MonoPrimitiveProperty(property: "windfury", owner: MinionProxy.self)
    var windfury: Bool

    @MonoPrimitiveProperty(property: "megaWindfury", owner: MinionProxy.self)
    var megaWindfury: Bool

    @MonoPrimitiveProperty(property: "golden", owner: MinionProxy.self)
    var golden: Bool

    @MonoPrimitiveField(field: "tier", owner: MinionProxy.self)
    var tier: Int32

    @MonoPrimitiveProperty(property: "reborn", owner: MinionProxy.self)
    var reborn: Bool

    @MonoPrimitiveProperty(property: "vanillaHealth", owner: MinionProxy.self)
    var vanillaHealth: Int32

    @MonoPrimitiveProperty(property: "vanillaAttack", owner: MinionProxy.self)
    var vanillaAttack: Int32

    @MonoPrimitiveProperty(property: "HasWingmen", owner: MinionProxy.self)
    var hasWingmen: Bool

    @MonoPrimitiveProperty(property: "game_id", owner: MinionProxy.self)
    var gameId: Int32
    
    @MonoPrimitiveProperty(property: "stealth", owner: MinionProxy.self)
    var stealth: Bool

    @MonoStringField(field: "minionName", owner: MinionProxy.self)
    var minionName: String

    func addDeathrattle(deathrattle: MonoHandle) {
        let field = mono_class_get_field_from_name(MinionProxy._class, "AdditionalDeathrattles")
        let inst = get()
        let obj = mono_field_get_value_object(MonoHelper._monoInstance, field, inst)
        
        let clazz = mono_object_get_class(obj)
        let method = mono_class_get_method_from_name(clazz, "Add", 1)
        
        let params = UnsafeMutablePointer<UnsafeMutablePointer<MonoObject>>.allocate(capacity: 1)

        params[0] = deathrattle.get()!
            
        _ = params.withMemoryRebound(to: UnsafeMutableRawPointer?.self, capacity: 1, {
            mono_runtime_invoke(method, obj, $0, nil)
        })
        params.deallocate()
    }
}
