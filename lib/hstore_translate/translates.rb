module HstoreTranslate
  module Translates
    def translates(*attrs)
      include InstanceMethods

      class_attribute :translated_attrs
      alias_attribute :translated_attribute_names, :translated_attrs # Improve compatibility with the gem globalize
      self.translated_attrs = attrs

      attrs.each do |attr_name|
        serialize attr_name, ActiveRecord::Coders::Hstore unless HstoreTranslate::native_hstore?

        define_method attr_name do
          read_hstore_translation(attr_name)
        end

        define_method "#{attr_name}=" do |value|
          write_hstore_translation(attr_name, value)
        end

        define_method "#{attr_name}_translations" do
          raw_translations(attr_name)
        end

        define_singleton_method "with_#{attr_name}_translation" do |value, locale = I18n.locale|
          quoted_translation_store = connection.quote_column_name(attr_name)
          where("#{quoted_translation_store} @> hstore(:locale, :value)", locale: locale, value: value)
        end

        I18n.available_locales.each do |locale|
          define_method "#{attr_name}_#{locale}" do
            read_hstore_translation(attr_name, locale)
          end

          define_method "#{attr_name}_#{locale}=" do |value|
            write_hstore_translation(attr_name, value, locale)
          end
        end
      end
    end

    # Improve compatibility with the gem globalize
    def translates?
      included_modules.include?(InstanceMethods)
    end

    module InstanceMethods
      def disable_fallback(&block)
        toggle_fallback(enabled = false, &block)
      end

      def enable_fallback(&block)
        toggle_fallback(enabled = true, &block)
      end

      protected

      def raw_translations(attr_name)
        self[attr_name] || {}
      end

      def hstore_translate_fallback_locales(locale)
        return if @enabled_fallback == false || !I18n.respond_to?(:fallbacks)
        I18n.fallbacks[locale]
      end

      def read_hstore_translation(attr_name, locale = I18n.locale)
        translations = raw_translations(attr_name)
        translation = translations[locale.to_s]

        if fallback_locales = hstore_translate_fallback_locales(locale)
          fallback_locales.each do |fallback_locale|
            t = translations[fallback_locale.to_s]
            if t && !t.empty? # differs from blank?
              translation = t
              break
            end
          end
        end

        translation
      end

      def write_hstore_translation(attr_name, value, locale = I18n.locale)
        translations = raw_translations(attr_name)

        if value.is_a?(Hash)
          translations = value
        else
          translations[locale.to_s] = value
        end

        send("#{attr_name}_will_change!")
        self[attr_name] = translations
        value
      end

      def toggle_fallback(enabled, &block)
        if block_given?
          old_value = @enabled_fallback
          begin
            @enabled_fallback = enabled
            yield
          ensure
            @enabled_fallback = old_value
          end
        else
          @enabled_fallback = enabled
        end
      end
    end
  end
end
