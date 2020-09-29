//
//  BleDevice.swift
//  TestBleApp
//
//  Created by Jaehong Yoo on 2020/06/12.
//  Copyright © 2020 Jaehong Yoo. All rights reserved.
//

import Foundation
import CoreBluetooth
import RxSwift
import RxRelay

open class BleDevice: NSObject {

    public enum ConnectionState : String {
        case CONNECTING = "CONNECTING"
        case DISCOVERING = "DISCONVERING"
        case CONNECTED = "CONNECTED"
        case DISCONNECTED = "DISCONNECTED"
        case DISCONNECTING = "DISCONNECTING"
    }
    
    class DisconnectedError : Error {}
    class CommunicationError : Error {}
    
    enum PushData {
        case ReadCharacteristicData(bleDevice: BleDevice, subject: ReplaySubject<Data>, characteristicUuid: String)
        case WriteCharacteristicData(bleDevice: BleDevice, subject: ReplaySubject<Data>, characteristicUuid: String, data: Data)
    }
    
    class AtomicValue<T> {
        let queue = DispatchQueue(label: "queue")

        private(set) var storedValue: T

        init(_ storedValue: T) {
            self.storedValue = storedValue
        }

        var value: T {
            get {
                return queue.sync {
                    self.storedValue
                }
            }
            set { // read, write 접근 자체는 atomic하지만,
                  // 다른 쓰레드에서 데이터 변경 도중(read, write 사이)에 접근이 가능하여, 완벽한 atomic이 아닙니다.
                queue.sync {
                    self.storedValue = newValue
                }
            }
        }

        // 올바른 방법
        func mutate(_ transform: (inout T) -> ()) {
            queue.sync {
                transform(&self.storedValue)
            }
        }
    }
    
    static var pushQueue = AtomicValue<[PushData]>([PushData]())
    static var pushing = AtomicValue<Bool>(false)
    static let dispatchQueue = DispatchQueue(label: "BleDevice")
    static func pushStart() {
        dispatchQueue.sync {
            doPush()
        }
    }
    static func doPush() {
        if (pushQueue.value.count > 0) {
            pushing.value = true
            let pushData = pushQueue.value.first!
            pushQueue.value.remove(at: 0)
            switch pushData {
            case .ReadCharacteristicData(let bleDevice, let subject, let uuid):
                bleDevice.processReadCharacteristicData(subject: subject, characteristicUuid: uuid)
            case .WriteCharacteristicData(let bleDevice, let subject, let uuid, let data):
                bleDevice.processWriteCharacteristicData(subject: subject, characteristicUuid: uuid, data: data)
            }
        } else {
            pushing.value = false
        }
    }
    
    public fileprivate(set) var connectionStateRelay = BehaviorRelay<ConnectionState>(value: ConnectionState.DISCONNECTED)
    public internal(set) var connectionState: ConnectionState = .DISCONNECTED {
        didSet {
            if (connectionState == .DISCONNECTED) {
                discoverSubject = PublishSubject<Any>()
            }
            connectionStateRelay.accept(connectionState)
        }
    }
    public var connected: Bool {
        return connectionState == ConnectionState.CONNECTED || connectionState == ConnectionState.DISCOVERING
    }
    fileprivate var disposable: Disposable! = nil
    fileprivate var peripheral: CBPeripheral! = nil
    fileprivate let characteristicSubject = ReplaySubject<CBCharacteristic>.createUnbounded()
    fileprivate var characteristicDic = [String: (subject: ReplaySubject<Data>, data: Data)]()
    fileprivate var notificationObservableDic = [String: (observable: Observable<Observable<Data>>, subject: ReplaySubject<Observable<Data>>)]()
    fileprivate var notificationDic = [String: PublishSubject<Data>]()
    fileprivate var discoverSubject = PublishSubject<Any>()
    fileprivate var discoverCompletable: Completable {
        return discoverSubject.ignoreElements()
    }

    public required init(_ peripheral: CBPeripheral) {
        self.peripheral = peripheral
        super.init()
        
        peripheral.delegate = self
    }
    
    public func connect() -> Completable {
        var dispose = true
        return BluetoothManager.instance.connectDevice(peripheral: peripheral)
            .concat(discoverCompletable.do(onSubscribe: {
                self.discover()
            }))
            .do( onError: { (error) in
                dispose = false
                self.connectionState = .DISCONNECTED
            }, onCompleted: {
                dispose = false
                self.connectionState = .CONNECTED
            }, onSubscribe: {
                self.connectionState = .CONNECTING
            }, onSubscribed: {
            }, onDispose: {
                if dispose {
                    self.disconnect()
                }
            })
    }
    
    public func disconnect() {
        _ = BluetoothManager.instance.disconnectDevice(peripheral: peripheral)
            .do(onSubscribe: {
                self.connectionState = .DISCONNECTING
            })
            .subscribe(onCompleted: {
                self.onDisconnected()
            }, onError: { (error) in
                debugPrint("disconnectDevice onError:\(error)")
            })
    }
    
    fileprivate func discover() {
        connectionState = .DISCOVERING
        peripheral.discoverServices(nil)
    }
    
    open func onDisconnected() {
        connectionState = .DISCONNECTED
    }
    
    public func getName() -> String? {
        return peripheral.name
    }
    
    public func getIdentifier() -> String {
        return peripheral.identifier.uuidString
    }
    
    public func readCharacteristic(uuid: String) -> Single<Data> {
        let subject = ReplaySubject<Data>.create(bufferSize: 1)
        return subject
            .do(onSubscribe: {
                BleDevice.pushQueue.value.append(.ReadCharacteristicData(bleDevice: self, subject: subject, characteristicUuid: uuid))
                BleDevice.pushStart()
            }, onDispose: {
                BleDevice.doPush()
            })
            .firstOrError()
    }
    
    public func writeCharacteristic(uuid: String, data: Data) -> Single<Data> {
        let subject = ReplaySubject<Data>.create(bufferSize: 1)
        return subject
            .do(onSubscribe: {
                BleDevice.pushQueue.value.append(.WriteCharacteristicData(bleDevice: self, subject: subject, characteristicUuid: uuid, data: data))
                BleDevice.pushStart()
            }, onDispose: {
                BleDevice.doPush()
            })
            .firstOrError()
    }
    
    public func setupNotification(uuid: String) -> Observable<Observable<Data>> {
        if notificationObservableDic[uuid] == nil {
            var isFirst = true
            let subject = ReplaySubject<Observable<Data>>.create(bufferSize: 1)
            notificationObservableDic[uuid] = (
                observable: subject.do(onSubscribe: {
                    if (isFirst) {
                        isFirst = false
                        self.processNotificationEnableData(subject: subject, characteristicUuid: uuid)
                    }
                }, onDispose: {
                    if (!subject.hasObservers) {
                        self.disableNotification(uuid: uuid)
                    }
                }), subject: subject)
        }
        return notificationObservableDic[uuid]!.observable
    }
    
    fileprivate func disableNotification(uuid: String) {
        notificationObservableDic.removeValue(forKey: uuid)
        notificationDic.removeValue(forKey: uuid)
        processNotificationDisableData(characteristicUuid: uuid)
    }
    
    fileprivate func processReadCharacteristicData(subject: ReplaySubject<Data>, characteristicUuid: String) {
        _ = getConnectedCompletable()
            .andThen(getCharacteristic(uuid: characteristicUuid))
            .flatMap { (characteristic) -> Single<Data> in
                let dataSubject = ReplaySubject<Data>.create(bufferSize: 1)
                self.characteristicDic[characteristicUuid] = (subject: dataSubject, data: Data())
                return Completable.create { (observer) -> Disposable in
                    self.readCharacteristicInner(characteristic: characteristic)
                    observer(.completed)
                    return Disposables.create()
                }
                .andThen(dataSubject.firstOrError())
                .timeout(DispatchTimeInterval.seconds(3), scheduler: ConcurrentDispatchQueueScheduler(qos: .background))
                .do(onError: { (error) in
                    self.characteristicDic.removeValue(forKey: characteristicUuid)
                })
            }
            .subscribe(onSuccess: { (data) in
                subject.on(.next(data))
            }, onError: { (error) in
                subject.on(.error(error))
            })
    }
    
    fileprivate func processWriteCharacteristicData(subject: ReplaySubject<Data>, characteristicUuid: String, data: Data) {
        _ = getConnectedCompletable()
            .andThen(getCharacteristic(uuid: characteristicUuid))
            .flatMap { (characteristic) -> Single<Data> in
                let dataSubject = ReplaySubject<Data>.create(bufferSize: 1)
                self.characteristicDic[characteristicUuid] = (subject: dataSubject, data: data)
                return Completable.create { (observer) -> Disposable in
                    self.writeCharacteristicInner(characteristic: characteristic, data: data)
                    observer(.completed)
                    return Disposables.create()
                }
                .andThen(dataSubject.firstOrError())
                .timeout(DispatchTimeInterval.seconds(3), scheduler: ConcurrentDispatchQueueScheduler(qos: .background))
                .do(onError: { (error) in
                    self.characteristicDic.removeValue(forKey: characteristicUuid)
                })
            }
            .subscribe(onSuccess: { (data) in
                subject.on(.next(data))
            }, onError: { (error) in
                subject.on(.error(error))
            })
    }
    
    fileprivate func processNotificationEnableData(subject: ReplaySubject<Observable<Data>>, characteristicUuid: String) {
        _ = getConnectedCompletable()
            .andThen(getCharacteristic(uuid: characteristicUuid))
            .flatMapCompletable({ (characteristic) -> Completable in
                Completable.create { (observer) -> Disposable in
                    self.setCharacteristicNotificationInner(characteristic: characteristic, data: true)
                    observer(.completed)
                    return Disposables.create()
                }
            })
            .subscribe(onCompleted: {
                let dataSubject = PublishSubject<Data>()
                self.notificationDic[characteristicUuid] = dataSubject
                subject.on(.next(dataSubject))
            }, onError: { (error) in
                subject.on(.error(error))
            })
    }
    
    fileprivate func processNotificationDisableData(characteristicUuid: String) {
        _ = getCharacteristic(uuid: characteristicUuid)
            .flatMapCompletable({ (characteristic) -> Completable in
                return Completable.create { (observer) -> Disposable in
                    self.setCharacteristicNotificationInner(characteristic: characteristic, data: false)
                    observer(.completed)
                    return Disposables.create()
                }
            })
            .subscribe(onCompleted: {
            }, onError: { (error) in
                debugPrint("getCharacteristic onError \(error)")
            })
    }
    
    fileprivate func getConnectedCompletable() -> Completable {
        return connectionStateRelay
            .filter { (connectionState) -> Bool in
                connectionState != .CONNECTING && connectionState != .DISCOVERING
            }
            .do(onNext: { (connectionState) in
                if (connectionState != .CONNECTED) {
                    throw DisconnectedError()
                }
            })
            .firstOrError()
            .asCompletable()
    }
    
    fileprivate func getCharacteristic(uuid: String) -> Single<CBCharacteristic> {
        return characteristicSubject
            .filter({ (characteristic) -> Bool in
                characteristic.uuid.uuidString == uuid
            })
            .take(DispatchTimeInterval.seconds(1), scheduler: ConcurrentDispatchQueueScheduler(qos: .background))
            .firstOrError()
    }
    
    fileprivate func readCharacteristicInner(characteristic: CBCharacteristic) {
        peripheral.readValue(for: characteristic)
    }
    
    fileprivate func writeCharacteristicInner(characteristic: CBCharacteristic, data: Data) {
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }
    
    fileprivate func setCharacteristicNotificationInner(characteristic: CBCharacteristic, data: Bool) {
        peripheral.setNotifyValue(data, for: characteristic)
    }
}

extension BleDevice: CBPeripheralDelegate {
    //CBPeripheralDelegate Override Methods
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        discoverSubject.onCompleted()
        if error != nil {
            debugPrint("error : peripheral didDiscoverServices: \(peripheral.name ?? peripheral.identifier.uuidString), error: \(error.debugDescription)")
        } else {
            self.peripheral = peripheral
            for service in peripheral.services! {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics! {
            characteristicSubject.on(.next(characteristic))
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let subjectAndData = characteristicDic[characteristic.uuid.uuidString] {
            characteristicDic.removeValue(forKey: characteristic.uuid.uuidString)
            subjectAndData.subject.on(.next(characteristic.value ?? subjectAndData.data))
        } else if let subject = notificationDic[characteristic.uuid.uuidString], let _value = characteristic.value {
            subject.on(.next(_value))
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let subjectAndData = characteristicDic[characteristic.uuid.uuidString] {
            characteristicDic.removeValue(forKey: characteristic.uuid.uuidString)
            subjectAndData.subject.on(.next(characteristic.value ?? subjectAndData.data))
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor descriptor: CBDescriptor, error: Error?) {
    }
}
