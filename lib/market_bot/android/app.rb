module MarketBot
  module Android
    class AppNotFoundError < StandardError; end

    class App
      MARKET_ATTRIBUTES = [:title, :rating, :updated, :current_version, :requires_android,
                          :category, :installs, :size, :price, :content_rating, :description,
                          :votes, :developer, :more_from_developer, :users_also_installed,
                          :related, :banner_icon_url, :banner_image_url, :website_url, :email,
                          :youtube_video_ids, :screenshot_urls, :whats_new, :permissions,
                          :rating_distribution, :html]

      attr_reader :app_id
      attr_reader *MARKET_ATTRIBUTES
      attr_reader :hydra
      attr_reader :callback
      attr_reader :error

      def self.parse(html)p
        result = {}

        doc = Nokogiri::HTML(html)

        elements = doc.css('.metadata .details-section-contents .meta-info')

        #(3..(elem_count - 1)).select{ |n| n.odd? }.each do |i|
        elements.each do |ele|
          field_name  = ele.elements.first.inner_text

          case field_name
          when 'Updated'
            result[:updated] = ele.elements.last.text.strip
          when 'Current Version'
            result[:current_version] = ele.elements.last.text.strip
          when 'Requires Android'
            result[:requires_android] = ele.elements.last.text.strip
          when 'Installs'
            result[:installs] = ele.elements.last.text.strip
          when 'Size'
            result[:size] = ele.elements.last.text.strip
          #when 'Price:'
          #  result[:price] = elements[i + 1].text
          when 'Content Rating'
            result[:content_rating] = ele.elements.last.text.strip
          end
        end

        result[:description] = doc.css('.show-more-content').first.inner_html
        result[:title] = doc.css('.document-title').text

        price_text = doc.css('.details-actions .buy-button-container .price').first.
            inner_text.gsub('Buy', '').strip
        result[:price] = price_text.include?('Install') ? 'Free' : price_text

        rating_elem = doc.css('.score')
        result[:rating] = rating_elem.first.text unless rating_elem.empty?

        votes_elem = doc.css('.reviews-num')
        result[:votes] = votes_elem.first.text unless votes_elem.empty?

        doc.css('.document-subtitle').each do |subtitle|
          if subtitle.attribute('class').to_s.include?('primary')
            result[:developer] = subtitle.inner_text.strip
          elsif subtitle.attribute('class').to_s.include?('category')
            result[:category] = subtitle.inner_text.strip
          end
        end

        result[:more_from_developer] = []
        result[:users_also_installed] = []
        result[:related] = []

        #if similar_elem = doc.css('.recommendation').first
        #  similar_elem.children.each do |similar_elem_child|
        #    assoc_app_type = similar_elem_child.attributes['data-analyticsid'].text
        #
        #    next unless %w(more-from-developer users-also-installed related).include?(assoc_app_type)
        #
        #    assoc_app_type = assoc_app_type.gsub('-', '_').to_sym
        #    result[assoc_app_type] ||= []
        #
        #    similar_elem_child.css('.app-left-column-related-snippet-container').each do |app_elem|
        #      assoc_app = {}
        #
        #      assoc_app[:app_id] = app_elem.attributes['data-docid'].text
        #
        #      result[assoc_app_type] << assoc_app
        #    end
        #  end
        #end

        result[:banner_icon_url] = doc.css('.cover-container img').first.attributes['src'].value

        #if image_elem = doc.css('.doc-banner-image-container img').first
        #  result[:banner_image_url] = image_elem.attributes['src'].value
        #else
        #  result[:banner_image_url] = nil
        #end

        if website_elem = doc.css('a').select{ |l| l.text.include?("Visit Developer's Website")}.first
          redirect_url = website_elem.attribute('href').value

          if q_param = URI(redirect_url).query.split('&').select{ |p| p =~ /q=/ }.first
            actual_url = q_param.gsub('q=', '')
          end

          result[:website_url] = actual_url
        end

        if email_elem = doc.css('a').select{ |l| l.text.include?("Email Developer")}.first
          result[:email] = email_elem.attribute('href').value.gsub(/^mailto:/, '')
        end

        unless (video_section_elem = doc.css('.play-click-target')).empty?
          #urls = video_section_elem.children.css('embed').map{ |e| e.attribute('src').value }
          urls = video_section_elem.attribute('data-video-url').value
          result[:youtube_video_ids] = [urls] #.map{ |u| /youtube\.com\/v\/(.*)\?/.match(u)[1] }
        else
          result[:youtube_video_ids] = []
        end

        screenshots = doc.css('.thumbnails img.screenshot')

        if screenshots && screenshots.length > 0
          result[:screenshot_urls] = screenshots.map { |s| s.attributes['src'].value }
        else
          result[:screenshot_urls] = []
        end

        result[:whats_new] = doc.css('.whatsnew .details-section-contents').inner_html

        result[:permissions] = permissions = []
        perm_types = ['dangerous', 'safe']
        perm_types.each do |type|
          doc.css("#doc-permissions-#{type} .doc-permission-group").each do |group_elem|
            title = group_elem.css('.doc-permission-group-title').text
            group_elem.css('.doc-permission-description').each do |desc_elem|
              #permissions << { :security => type, :group => title, :description => desc_elem.text }
            end
            descriptions = group_elem.css('.doc-permission-description').map { |e| e.text }
            descriptions_full = group_elem.css('.doc-permission-description-full').map { |e| e.text }
            (0...descriptions.length).each do |i|
              desc = descriptions[i]
              desc_full = descriptions_full[i]
              permissions << { :security => type, :group => title, :description => desc, :description_full => desc_full }
            end
          end
        end

        result[:rating_distribution] = { 5 => nil, 4 => nil, 3 => nil, 2 => nil, 1 => nil }

        #if (histogram = doc.css('.rating-histogram').first)
        #  cur_index = 5
        #  histogram.children.each do |e|
        #    result[:rating_distribution][cur_index] = e.children.last.inner_text.gsub(/[^0-9]/, '').to_i
        #    cur_index -= 1
        #  end
        #end
        histograms = doc.css('.rating-histogram .rating-bar-container .bar-number').map{|i| i.inner_text}
        histograms.each_with_index do |val, index|
          a = 5-index
          result[:rating_distribution][a] = val
        end

        result[:html] = html

        result
      end

      def initialize(app_id, options={})
        @app_id = app_id
        @hydra = options[:hydra] || MarketBot.hydra
        @request_opts = options[:request_opts] || {}
        @callback = nil
        @error = nil
      end

      def market_url
        "https://play.google.com/store/apps/details?id=#{@app_id}&hl=en"
      end

      def update
        resp = Typhoeus::Request.get(market_url, @request_opts)
        raise MarketBot::Android::AppNotFoundError if resp.response_code==404
        result = App.parse(resp.body)
        update_callback(result)

        self
      end

      def enqueue_update(&block)
        @callback = block
        @error = nil

        request = Typhoeus::Request.new(market_url, @request_opts)

        request.on_complete do |response|
          # HACK: Typhoeus <= 0.4.2 returns a response, 0.5.0pre returns the request.
          response = response.response if response.is_a?(Typhoeus::Request)

          result = nil

          begin
            result = App.parse(response.body)
          rescue Exception => e
            @error = e
          end

          update_callback(result)
        end

        hydra.queue(request)

        self
      end

    private
      def update_callback(result)
        unless @error
          MARKET_ATTRIBUTES.each do |a|
            attr_name = "@#{a}"
            attr_value = result[a]
            instance_variable_set(attr_name, attr_value)
          end
        end

        @callback.call(self) if @callback
      end
    end

  end
end
