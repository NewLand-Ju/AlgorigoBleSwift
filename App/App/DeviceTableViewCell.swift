//
//  DeviceTableViewCell.swift
//  TestApp
//
//  Created by Jaehong Yoo on 2020/08/28.
//  Copyright © 2020 Algorigo. All rights reserved.
//

import UIKit
import AlgorigoBleLibrary

protocol DeviceTableViewCellDelegate {
    func handleConncectBtn(device: BleDevice)
}

class DeviceTableViewCell: UITableViewCell {

    @IBOutlet weak var titleView: UILabel!
    @IBOutlet weak var connectBtn: UIButton!
    
    var delegate: DeviceTableViewCellDelegate!

    var device: BleDevice? {
        didSet {
            titleView.text = device?.getName() ?? device?.getIdentifier()
            print("connectionState:\(device?.connectionState)")
            switch device?.connectionState {
            case .CONNECTED:
                connectBtn.setTitle("Disconnect", for: .normal)
                connectBtn.isEnabled = true
            case .DISCONNECTED, .DISCONNECTING:
                connectBtn.setTitle("Connect", for: .normal)
                connectBtn.isEnabled = true
            case .CONNECTING, .DISCOVERING:
                connectBtn.setTitle("Connecting...", for: .normal)
                connectBtn.isEnabled = false
            default:
                break
            }
        }
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }
    
    @IBAction func handleConnectBtn() {
        if let device = device {
            print("handleConnectBtn:\(device.getName() ?? device.getIdentifier())")
            delegate.handleConncectBtn(device: device)
        }
    }
}
