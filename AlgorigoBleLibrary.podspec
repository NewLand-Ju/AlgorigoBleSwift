Pod::Spec.new do |spec|
spec.name         = "AlgorigoBleLibrary"
spec.version      = "0.0.1"
spec.summary      = "Swift Ble Library using RxSwift by Algorigo"
spec.description  = <<-DESC
Swift Ble Library using RxSwift by Algorigo
write by rouddy@naver.com
DESC

spec.homepage     = "https://github.com/Algorigo/AlgorigoBleLibrarySwift"
spec.license      = { :type => 'MIT', :file => 'LICENSE.md' }
spec.author       = { "author" => "rouddy@naver.com" }
spec.documentation_url = "https://github.com/Algorigo/AlgorigoBleLibrarySwift"

spec.ios.deployment_target = '13.0'

spec.swift_version = '5.1'
spec.source       = { :git => "https://github.com/Algorigo/AlgorigoBleLibrarySwift.git", :tag => "#{spec.version}" }
spec.source_files  = "AlgorigoBleLibrary/AlgorigoBleLibrary/*.swift"

spec.dependency 'RxSwift', '~> 5.1.1'
spec.dependency 'RxRelay', '~> 5.1.1'

end
