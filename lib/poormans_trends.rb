module Poormans
  module Trends
    # 
    # To be self-sufficient, this action prints 3 things
    # 
    def poormans_trends
      if params[:id] == 'scripts'
        # 
        # 1. Javascripts required
        # 
        render :text => ["jquery-1.2.1.js", "excanvas-compressed.js", "fgCharting.jQuery.js"].inject("") { |sum, filename|
          sum + "\n" + open(File.join(File.dirname(__FILE__), '..', 'js', filename)) {|f| f.read }
        }, :content_type => 'text/javascript'
        return
      end

      respond_to do |format|
        format.html {
          # 
          # 2. Welcome HTML form
          # 
          render :file => File.join(File.dirname(__FILE__), '..', 'views', 'poormans_trends.html.erb')
        }

        format.json {
          # 
          # 3. HTML partial for each selected model
          # 
          klass = params[:id].constantize
          return render :text => klass.name unless klass.respond_to? :find_by_sql
        
          instance = klass.new
          date_col = params[:date_col] || 'created_at'
          @max_rows = params[:max_rows] || 8
          @max_cols = params[:max_cols] || 10
          @all_columns = instance.attributes.keys        
          return render :text => [klass.count, @all_columns].inspect unless instance.attributes.keys.include?(date_col)
          
          foreign_keys = @all_columns.select {|x| x =~ /_id$/}
          type_cols    = @all_columns.select {|x| x =~ /(^type|_type)$/ }
          @columns = foreign_keys + type_cols
          @top_values = {}
          @ass_lookup = {}
          @ass_lookup['_total_'] = Proc.new { |i| 'Total' }
        
          @columns.each do |col|
            @ass_lookup[col] = create_lookup(klass, col)
            @top_values[col] = klass.find(:all, {
              :select => "COUNT(*) as #{col}_count, #{col}",
              :conditions => ["FLOOR(DATEDIFF(NOW(), #{date_col}) / 7) <= ?", @max_cols],
              :group => col,
              :order => "#{col}_count DESC",
              :limit => @max_rows,
            }).collect do |row| 
              popular_value = row.send :attribute_before_type_cast, col
              breakdown_by_date = klass.find(:all, {
                :select => "FLOOR(DATEDIFF(NOW(), #{date_col}) / 7) AS week_col, COUNT(*) AS week_count",
                :conditions => { col => popular_value },
                :group => "week_col",
                :order => "week_col ASC",
                :limit => @max_cols,
              }).inject({}) {|sum, row2| sum.merge({row2.week_col => row2.week_count}) }
              { popular_value => breakdown_by_date }
            end
          end
          @columns.unshift "_total_"
          breakdown_by_date = klass.find(:all, {
            :select => "FLOOR(DATEDIFF(NOW(), #{date_col}) / 7) AS week_col, COUNT(*) AS week_count",
            :group => "week_col",
            :order => "week_col ASC",
            :limit => @max_cols,
          }).inject({}) {|sum, row2| sum.merge({row2.week_col => row2.week_count}) }
          @top_values["_total_"] = [{ "total" => breakdown_by_date }]
          render :file => File.join(File.dirname(__FILE__), '..', 'views', 'table.html.erb')
        }
      end
    rescue
      @classname=params[:id]
      render :file => File.join(File.dirname(__FILE__), '..', 'views', 'error.html.erb')
    end

    def create_lookup(klass, colname)
      Proc.new do |i|
        type = colname.gsub(/_id$/, '').to_sym
        rel = klass.reflect_on_association(type)
        if rel && i
          sym = rel.klass.respond_to?(:get_cache) ? :get_cache : :find
          ob = rel.klass.send(sym, i)
        else
          i ? i : 'nil'
        end
      end
    end

  end
end