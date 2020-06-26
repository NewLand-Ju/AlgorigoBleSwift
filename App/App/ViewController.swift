//
//  ViewController.swift
//  TestApp
//
//  Created by Jaehong Yoo on 2020/08/28.
//  Copyright © 2020 Algorigo. All rights reserved.
//

import UIKit
import AlgorigoBleLibrary
import RxSwift

class ViewController: UIViewController {

    private var disposable: Disposable? = nil
    private var disposableBag = DisposeBag()
    private var scanning: Bool {
        return disposable != nil
    }
    private var devices = [BleDevice]()
    
    @IBOutlet weak var tableView: UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        let nibName = UINib(nibName: "DeviceTableViewCell", bundle: nil)
        self.tableView.register(nibName, forCellReuseIdentifier: "deviceCell")
        
        BluetoothManager.instance.getConnectionStateObservable()
            .observeOn(MainScheduler.instance)
            .subscribe { [weak self] (event) in
                switch event {
                case .next(let status):
                    print("next:\(status.bleDevice):\(status.connectionState)")
                    self?.tableView.reloadData()
                default:
                    break
                }
            }
            .disposed(by: disposableBag)
    }

    override func viewWillDisappear(_ animated: Bool) {
        stopScan()
    }
    
    @IBAction func handleScanBtn() {
        if scanning {
            stopScan()
        } else {
            startScan()
        }
    }
    
    private func startScan() {
        disposable = BluetoothManager.instance.scanDevice()
            .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .background))
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { [weak self] (devices) in
                print("scanDevice onNext:\(devices.map { $0.getName() ?? $0.getIdentifier()})")
                self?.devices = devices
                self?.tableView.reloadData()
            }, onError: { (error) in
                print("scanDevice onError:\(error)")
            }, onCompleted: {
                print("scanDevice onCompleted")
            }, onDisposed: {
                print("scanDevice onDisposed")
            })
    }
    
    private func stopScan() {
        disposable?.dispose()
        disposable = nil
    }
}

extension ViewController : UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return devices.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "deviceCell", for: indexPath) as? DeviceTableViewCell ?? DeviceTableViewCell()
        cell.delegate = self
        cell.device = devices[indexPath.row]
        return cell
    }
}

extension ViewController : DeviceTableViewCellDelegate {
    func handleConncectBtn(device: BleDevice) {
        switch device.connectionState {
        case .CONNECTED:
            device.disconnect()
            self.tableView.reloadData()
        case .DISCONNECTED:
            _ = device.connect()
                .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .background))
                .observeOn(MainScheduler.instance)
                .subscribe(onCompleted: {
                    print("viewController onCompleted")
                }, onError: { (error) in
                    print("viewController onError:\(error)")
                })
        default:
            break
        }
    }
}
