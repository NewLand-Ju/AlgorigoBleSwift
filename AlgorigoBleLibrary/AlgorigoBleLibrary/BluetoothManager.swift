//
//  RxBluetoothManager.swift
//  TestBleApp
//
//  Created by Jaehong Yoo on 2020/06/09.
//  Copyright © 2020 Jaehong Yoo. All rights reserved.
//

import Foundation
import CoreBluetooth
import RxSwift
import RxRelay


public protocol BleDeviceDelegate {
    func createBleDevice(peripheral: CBPeripheral) -> BleDevice?
//    func getBleScanSetting() -> BleScanSetting
//    func getBleScanFilters() -> [BleScanFilter]
}
extension BleDeviceDelegate {
    func createBleDeviceOuter(peripheral: CBPeripheral) -> BleDevice? {
        return createBleDevice(peripheral: peripheral)
    }
}

public class BluetoothManager : NSObject, CBCentralManagerDelegate {
    
    class RxBluetoothError : Error {
        let error: Error?
        init(_ error: Error?) {
            self.error = error
        }
    }
    
    enum BluetoothCentralManagerError : Error {
        case BluetoothUnknownError
        case BluetoothResettingError
        case BluetoothUnsupportedError
        case BluetoothUnauthorizedError
        case BluetoothPowerOffError
    }
    
    public class DefaultBleDeviceDelegate : BleDeviceDelegate {
        public func createBleDevice(peripheral: CBPeripheral) -> BleDevice? {
            BleDevice(peripheral)
        }
    }
    
    public static let instance = BluetoothManager()
    
    private static let service = CBUUID(string: "F000AA20-0451-4000-B000-000000000000")
    
    fileprivate var manager: CBCentralManager! = nil
    fileprivate var deviceDic = [CBPeripheral: BleDevice]()
    public var bleDeviceDelegate: BleDeviceDelegate = DefaultBleDeviceDelegate()
    fileprivate let initializedSubject = ReplaySubject<CBManagerState>.create(bufferSize: 1)
    fileprivate let connectionStateSubject = PublishSubject<(bleDevice: BleDevice, connectionState: BleDevice.ConnectionState)>()
    fileprivate let scanSubject = PublishSubject<CBPeripheral>()
    fileprivate var connectSubjects = [CBPeripheral: PublishSubject<Bool>]()
    fileprivate var disconnectSubjects = [CBPeripheral: PublishSubject<Bool>]()
    fileprivate var disposeBag = DisposeBag()
    
    override private init() {
        super.init()
        self.manager = CBCentralManager(delegate: self, queue: nil)
    }
    
    public func initialize(bleDeviceDelegate: BleDeviceDelegate) {
        self.bleDeviceDelegate = bleDeviceDelegate
    }
    
    public func scanDevice(withServices services: [String]? = nil) -> Observable<[BleDevice]> {
        var bleDeviceList = [BleDevice]()
        return scanDeviceInner(withServices: services)
            .map { (peripheral) -> [BleDevice] in
                let device = self.onBluetoothDeviceFound(peripheral)
                if let _device = device {
                    if !bleDeviceList.contains(where: { (a) -> Bool in _device == a }) {
                        bleDeviceList.append(_device)
                    }
                }
                return bleDeviceList
            }
    }
    
    public func scanDevice(withServices services: [String]? = nil, intervalSec: Int) -> Observable<[BleDevice]> {
        return scanDevice(withServices: services)
        .takeUntil(Observable<Int>.timer(DispatchTimeInterval.seconds(intervalSec), scheduler: ConcurrentDispatchQueueScheduler(qos: .background)))
    }
    
    private func scanDeviceInner(withServices services: [String]? = nil) -> Observable<CBPeripheral> {
        return checkBluetoothStatus()
            .andThen(scanSubject
                .do(onSubscribe: {
                    if !self.scanSubject.hasObservers {
                        let services = services?.map({ (uuidStr) -> CBUUID? in
                            CBUUID(string: uuidStr)
                        }).compactMap({ $0 })
                        self.manager.scanForPeripherals(withServices: services, options: [CBCentralManagerScanOptionAllowDuplicatesKey : false])
                    }
                }, onDispose: {
                    if !self.scanSubject.hasObservers {
                        self.manager.stopScan()
                    }
                }))
    }
    
    fileprivate func checkBluetoothStatus() -> Completable {
        return initializedSubject
            .do(onNext: { (state) in
                switch (state) {
                case .unknown:
                    throw BluetoothCentralManagerError.BluetoothUnknownError
                case .resetting:
                    throw BluetoothCentralManagerError.BluetoothResettingError
                case .unsupported:
                    throw BluetoothCentralManagerError.BluetoothUnsupportedError
                case .unauthorized:
                    throw BluetoothCentralManagerError.BluetoothUnauthorizedError
                case .poweredOff:
                    throw BluetoothCentralManagerError.BluetoothPowerOffError
                case .poweredOn:
                    break
                @unknown default:
                    throw BluetoothCentralManagerError.BluetoothUnknownError
                }
            })
            .first()
            .asCompletable()
    }
    
    fileprivate func onBluetoothDeviceFound(_ peripheral: CBPeripheral) -> BleDevice? {
        return deviceDic[peripheral] ?? createBleDevice(peripheral)
    }
    
    fileprivate func createBleDevice(_ peripheral: CBPeripheral) -> BleDevice? {
        let device = bleDeviceDelegate.createBleDeviceOuter(peripheral: peripheral)
        if let _device = device {
            deviceDic[peripheral] = _device
            _device.connectionStateRelay
                .subscribe { [weak self] (event) in
                    switch event {
                    case .next(let state):
                        self?.connectionStateSubject.onNext((bleDevice: _device, connectionState: state))
                    default:
                        break
                    }
                }
                .disposed(by: disposeBag)
        }
        return device
    }
    
    public func getDevices() -> [BleDevice] {
        return Array(deviceDic.values)
    }
    
    public func getConnectedDevices() -> [BleDevice] {
        return deviceDic.values.filter { (bleDevice) -> Bool in
            bleDevice.connectionState == .CONNECTED
        }
    }
    
    public func getConnectionStateObservable() -> Observable<(bleDevice: BleDevice, connectionState: BleDevice.ConnectionState)> {
        return connectionStateSubject
    }
    
    func connectDevice(peripheral: CBPeripheral) -> Completable {
        return checkBluetoothStatus()
            .andThen(Completable.deferred({ () -> PrimitiveSequence<CompletableTrait, Never> in
                if let subject = self.connectSubjects[peripheral] {
                    return subject
                        .ignoreElements()
                } else {
                    let subject = PublishSubject<Bool>()
                    self.connectSubjects[peripheral] = subject
                    return subject
                        .ignoreElements()
                        .do(onSubscribe: {
                            self.manager.connect(peripheral, options: nil)
                        }, onDispose: {
                            self.connectSubjects.removeValue(forKey: peripheral)
                        })
                }
            }))
    }
    
    func disconnectDevice(peripheral: CBPeripheral) -> Completable {
        return Completable.deferred { () -> PrimitiveSequence<CompletableTrait, Never> in
            if let subject = self.disconnectSubjects[peripheral] {
                return subject
                    .ignoreElements()
            } else {
                let subject = PublishSubject<Bool>()
                self.disconnectSubjects[peripheral] = subject
                return subject
                    .ignoreElements()
                    .do(onSubscribe: {
                        self.manager.cancelPeripheralConnection(peripheral)
                    }, onDispose: {
                        self.disconnectSubjects.removeValue(forKey: peripheral)
                    })
            }
        }
    }
    
    //CBCentralManagerDelegate Override Methods
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        initializedSubject.onNext(central.state)
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        scanSubject.onNext(peripheral)
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if let subject = connectSubjects[peripheral] {
            subject.on(.completed)
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if let subject = connectSubjects[peripheral] {
            subject.on(.error(RxBluetoothError(error)))
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let subject = disconnectSubjects[peripheral] {
            subject.on(.completed)
        } else if let device = deviceDic[peripheral] {
            device.onDisconnected()
            connectionStateSubject.onNext((bleDevice: device, connectionState: BleDevice.ConnectionState.DISCONNECTED))
        }
    }
}
