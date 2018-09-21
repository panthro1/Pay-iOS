//
//  AddressQRCodeController.swift
//  BankexWallet
//
//  Created by Korovkina, Ekaterina on 3/13/2561 BE.
//  Copyright © 2561 Alexander Vlasov. All rights reserved.
//

import UIKit
import web3swift

class AddressQRCodeController: BaseViewController {

    var addressToGenerateQR: String?

    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var addressLabel: UILabel!
    @IBOutlet weak var walletNameLabel: UILabel!
    @IBOutlet weak var copyAddressButton: UIButton!

    let keysService: SingleKeyService  = SingleKeyServiceImplementation()
    var navTitle: String?
    lazy var clipView:UIView = {
        let clipView = UIView()
        clipView.backgroundColor = UIColor(hex: "B8BFC9")
        return clipView
    }()

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupClipboardView()
        navigationController?.setNavigationBarHidden(false, animated: true)
        updateUI()
    }
    
    private func updateUI() {
        self.title = navTitle ?? NSLocalizedString("Receive", comment: "")
        imageView.image = generateQRCode(from: addressToGenerateQR)
        addressLabel.text = addressToGenerateQR?.lowercased()
        walletNameLabel.text = keysService.selectedWallet()?.name
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupNavBar()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
    }
    
    private func setupNavBar() {
        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        let sendButton = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareAddress(_:)))
        self.navigationItem.rightBarButtonItem = sendButton
        addBackButton()
    }
    
    private func addBackButton() {
        let button = UIButton(type: .system)
        button.setImage(UIImage(named: "BackArrow"), for: .normal)
        button.setTitle(" Wallet", for: .normal)
        button.setTitleColor(WalletColors.mainColor, for: .normal)
        //button.frame = CGRect(x: 0, y: 0, width: 100, height: 30)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 17)
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: button)
        button.addTarget(self, action: #selector(backButtonTapped), for: .touchUpInside)
    }
    
    @objc func backButtonTapped() {
        navigationController?.popViewController(animated: true)
    }
    
    private func setupClipboardView() {
        clipView.frame = CGRect(x: 0, y: view.bounds.maxY, width: view.bounds.width, height: 58.0)
        let heightLabel = clipView.bounds.height/2
        let label = UILabel(frame: CGRect(x: 0, y: clipView.bounds.midY - heightLabel/2, width: clipView.bounds.width, height: heightLabel))
        label.textAlignment = .center
        label.text = "Passphrase copied to clipboard"
        label.textColor = UIColor(hex: "F9FAFC")
        label.font = UIFont.systemFont(ofSize: 15.0)
        clipView.addSubview(label)
        self.view.addSubview(clipView)
    }
    


    @objc func shareAddress(_ sender : UIBarButtonItem) {

        let addressToShare: String = addressToGenerateQR ?? ""

        let itemsToShare = [ addressToShare ]
        let activityViewController = UIActivityViewController(activityItems: itemsToShare, applicationActivities: nil)
        activityViewController.popoverPresentationController?.sourceView = self.view // so that iPads won't crash

        // exclude some activity types from the list (optional)
        activityViewController.excludedActivityTypes = [ UIActivityType.airDrop, UIActivityType.postToFacebook, UIActivityType.mail, UIActivityType.message, UIActivityType.postToTwitter ]

        self.present(activityViewController, animated: true, completion: nil)
    }


    @IBAction func copyAddress(_ sender: Any) {
        UIPasteboard.general.string = addressToGenerateQR
        UIView.animate(withDuration: 0.7, animations: {
            self.clipView.frame.origin.y = self.view.bounds.maxY - 58.0
        }) { _ in
            UIView.animate(withDuration: 0.7, delay: 0.5, options: .curveEaseInOut, animations: {
                self.clipView.frame.origin.y = self.view.bounds.maxY
            })
        }
    }

    func generateQRCode(from string: String?) -> UIImage? {
        guard let string = string else {
            return nil
        }
        var code: String
        if let c = Web3.EIP67Code(address: string)?.toString() {
            code = c
        } else {
            code = string
        }

        let data = code.data(using: String.Encoding.ascii)

        if let filter = CIFilter(name: "CIQRCodeGenerator") {
            filter.setValue(data, forKey: "inputMessage")
            let transform = CGAffineTransform(scaleX: 3, y: 3)

            if let output = filter.outputImage?.transformed(by: transform) {
                return UIImage(ciImage: output)
            }
        }

        return nil
    }
}
