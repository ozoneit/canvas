module Canvas::Plugins::Validators::RespondusSoapEndpointPluginValidator
  def self.validate(settings, plugin_setting)
    settings = settings.with_indifferent_access.slice(:enabled)
    if settings[:enabled] && !Canvas::Plugin.find(:qti_exporter).settings[:enabled]
      plugin_setting.errors.add_to_base('QTI Exporter plugin must be enabled first')
      false
    else
      settings
    end
  end
end
