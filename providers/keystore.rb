use_inline_resources

def whyrun_supported?
	true
end

def java_version
	node["java"]["jdk_version"] || node["languages"]["java"]["version"].sub(/^1\.([0-9]+)\..*/, '\1')
end

action :generate do
	bin_path = new_resource.java_bin_path || ::File.join(node["java"]["java_home"], "bin")
	_command = "#{bin_path}/keytool -genkeypair -keystore #{new_resource.keystore_path}" +
			" -dname '#{new_resource.dn}' -alias '#{new_resource.cert_alias}'" +
			" -keypass #{new_resource.password} -storepass #{new_resource.password}"
	
	if new_resource.x509_extensions
		if java_version > "6"
			_command += " " + new_resource.x509_extensions.map do |k,v|
				if v
					"-ext #{k}=#{v}"
				else
					"-ext #{k}"
				end
			end.join(" ")
		else
			::Chef::Log.warn "x509_extensions is not supported on java 6 keytool"
		end
	end

	_command += " -validity #{new_resource.validity}" if new_resource.validity
	_command += " -keyalg #{new_resource.keyalg}" if new_resource.keyalg
	
	execute "generate private key" do
		command _command
		user new_resource.owner
		group new_resource.group
		not_if "#{bin_path}/keytool -list -keystore #{new_resource.keystore_path} " +
			" -keypass #{new_resource.password} -storepass #{new_resource.password}" +
			" -rfc -alias '#{new_resource.cert_alias}'"
		notifies :create, "ruby_block[execute block with_certificate]", :immediately if new_resource.with_certificate.is_a?(Proc)
	end

	file new_resource.keystore_path do
		owner new_resource.owner
		group new_resource.group
		mode new_resource.mode
	end

  if new_resource.with_certificate.is_a?(Proc)
    ruby_block "execute block with_certificate" do
      block do
        extend ::Chef::Mixin::ShellOut
        cert = shell_out!("#{bin_path}/keytool -exportcert -keystore #{new_resource.keystore_path}" +
        " -alias '#{new_resource.cert_alias}'" +
        " -keypass #{new_resource.password} -storepass #{new_resource.password} -rfc").stdout
        new_resource.with_certificate.call(cert)
      end
      action :nothing
    end
  end
end
