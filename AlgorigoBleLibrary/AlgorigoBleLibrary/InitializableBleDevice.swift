//
//  InitializableBleDevice.swift
//  AlgorigoBleLibrary
//
//  Created by rouddy on 2020/09/24.
//  Copyright © 2020 Jaehong Yoo. All rights reserved.
//

import Foundation
import RxSwift
import RxRelay
import CoreBluetooth

open class InitializableBleDevice: BleDevice {
    
    private var initialized = false
    private let initialzeRelay = PublishRelay<ConnectionState>()
    
    required public init(_ peripheral: CBPeripheral) {
        super.init(peripheral)
    }
    
    public override var connectionState: BleDevice.ConnectionState {
        get {
            if super.connectionState == .CONNECTED && !initialized {
                return .DISCOVERING
            } else {
                return super.connectionState
            }
        }
        set {
            super.connectionState = newValue
        }
    }
    
    public override var connected: Bool {
        get {
            super.connected && initialized
        }
    }
    
    public override func connect() -> Completable {
        super.connect()
            .concat(getInitialize())
    }
    
    private func getInitialize() -> Completable {
        Completable.deferred { [weak self] () -> PrimitiveSequence<CompletableTrait, Never> in
            self?.initialzeCompletable() ?? Completable.never()
        }
        .do(onCompleted: { [weak self] in
            self?.connectionState = .CONNECTED
            self?.initialized = true
        })
    }
    
    //Abstract
    open func initialzeCompletable() -> Completable {
        fatalError("Subsclasses need to implement the 'scannedIdentifier' method.")
    }
    
    open override func onDisconnected() {
        super.onDisconnected()
        initialized = false
    }
}
