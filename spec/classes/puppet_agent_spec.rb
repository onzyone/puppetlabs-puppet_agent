require 'spec_helper'

describe 'puppet_agent' do
  package_version = '1.2.5'
  global_params = {
    :package_version => package_version
  }

  context 'supported operating systems' do
    on_supported_os.each do |os, facts|
      context "on #{os}" do
        let(:facts) do
          if os =~ /sles/
            facts.merge({
              :is_pe => true,
              :operatingsystemmajrelease => facts[:operatingsystemrelease].split('.')[0],
            })
          elsif os =~ /solaris/
            facts.merge({
              :is_pe => true,
            })
          else
            facts
          end
        end

        before(:each) do
          if os =~ /sles/ || os =~ /solaris/
            # Need to mock the PE functions

            Puppet::Parser::Functions.newfunction(:pe_build_version, :type => :rvalue) do |args|
              '4.0.0'
            end

            Puppet::Parser::Functions.newfunction(:pe_compiling_server_aio_build, :type => :rvalue) do |args|
              '1.2.5'
            end
          end
        end

        context 'invalid package_versions' do
          ['1.3.5banana', '1.2', '10-q-5'].each do |version|
            let(:params) { { :package_version => version } }

            it { expect { catalogue }.to raise_error(/invalid version/) }
          end
        end

        context 'valid package_versions' do
          ['1.4.0.30.g886c5ab', '1.4.0', '1.4.0-10', '1.4.0.10'].each do |version|
            let(:params) { { :package_version => version } }

            it { is_expected.to compile.with_all_deps }
            it { expect { catalogue }.not_to raise_error }
          end
        end

        [{}, {:service_names => []}].each do |params|
          context "puppet_agent class without any parameters" do
            let(:params) { params.merge(global_params) }

            it { is_expected.to compile.with_all_deps }

            it { is_expected.to contain_class('puppet_agent') }
            it { is_expected.to contain_class('puppet_agent::params') }
            it { is_expected.to contain_class('puppet_agent::prepare') }
            it { is_expected.to contain_class('puppet_agent::install').that_requires('puppet_agent::prepare') }

            if facts[:osfamily] == 'RedHat'
              # Workaround PUP-5802/PUP-5025
              yum_package_version = package_version + '-1.el' + facts[:operatingsystemmajrelease]
              it { is_expected.to contain_package('puppet-agent').with_ensure(yum_package_version) }
            elsif facts[:osfamily] == 'Debian'
              # Workaround PUP-5802/PUP-5025
              deb_package_version = package_version + '-1' + facts[:lsbdistcodename]
              it { is_expected.to contain_package('puppet-agent').with_ensure(deb_package_version) }
            elsif facts[:osfamily] == 'Solaris' && (facts[:operatingsystemmajrelease] == '10' || Puppet.version < '4.0.0')
              it { is_expected.to contain_package('puppet-agent').with_ensure('present') }
            else
              it { is_expected.to contain_package('puppet-agent').with_ensure(package_version) }
            end

            if Puppet.version < "4.0.0" && !params[:is_pe]
              it { is_expected.to contain_class('puppet_agent::service').that_requires('puppet_agent::install') }
            end

            if params[:service_names].nil? &&
              !(facts[:osfamily] == 'Solaris' and facts[:operatingsystemmajrelease] == '11') &&
              Puppet.version < "4.0.0" && !params[:is_pe]
              it { is_expected.to contain_service('puppet') }
              it { is_expected.to contain_service('mcollective') }
            else
              it { is_expected.to_not contain_service('puppet') }
              it { is_expected.to_not contain_service('mcollective') }
            end
          end
        end
      end
    end
  end

  context 'unsupported operating system' do
    describe 'puppet_agent class without any parameters on Solaris/Nexenta' do
      let(:facts) {{
        :osfamily        => 'Solaris',
        :operatingsystem => 'Nexenta',
        :puppet_ssldir   => '/dev/null/ssl',
        :puppet_config   => '/dev/null/puppet.conf',
        :architecture    => 'i386',
      }}
      let(:params) { global_params }

      it { is_expected.to raise_error(Puppet::Error, /Nexenta not supported/) }
    end
  end
end
