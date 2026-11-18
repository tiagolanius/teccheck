Pod::Spec.new do |s|
  s.name             = 'teccheck_native'
  s.version          = '1.0.0'
  s.summary          = 'Recursos nativos de rede do TecCheck.'
  s.description      = 'ICMP echo/TTL, permissão de localização e abertura do Speedtest.'
  s.homepage         = 'https://github.com/'
  s.license          = { :type => 'MIT' }
  s.author           = { 'DFSolutions' => 'contato@dfsolutions.local' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '12.0'
  s.swift_version    = '5.0'
  s.frameworks       = 'CoreLocation'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
