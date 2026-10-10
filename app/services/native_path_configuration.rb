# What the native apps are told about our paths. The iOS app bundles a copy of
# this as its fallback (PartitaDoppia/Resources/path-configuration.json); keep
# the two in step.
module NativePathConfiguration
  MODAL_PATHS = %w[/new$ /edit$ /copy$ /email$ /payments/new$].freeze

  def self.ios_v1
    {
      settings: {},
      rules: [
        { patterns: [ ".*" ], properties: { context: "default", pull_to_refresh_enabled: true } },
        { patterns: MODAL_PATHS, properties: { context: "modal", pull_to_refresh_enabled: false } }
      ]
    }
  end
end
