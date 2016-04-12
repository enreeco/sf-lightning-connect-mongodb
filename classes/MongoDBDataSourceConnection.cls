//https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_namespace_DataSource.htm
global class MongoDBDataSourceConnection extends DataSource.Connection { 
    
    private static String NC_NAME = 'MongoDB';
    private static String DB_ENDPOINT_NC = 'callout:'+NC_NAME+'/lighthningconnect/invoices';
    private String DB_ENDPOINT{
        get{
            return [Select Endpoint From NamedCredential Where DeveloperName = :NC_NAME].endpoint;
        }
    }
    global MongoDBDataSourceConnection(DataSource.ConnectionParams connectionParams) {
    }
    
    private static Map<String,String> FIELD_MAP = new Map<String,String>{
            'Id' => '_id',
            'ExternalId' => '_id',
            'DisplayUrl' => '_id',
            'Account' => 'accountid',
            'Contract' => 'contractid',
            'CreatedDate' => 'created',
            'Amount' => 'amount',
            'Description' => 'description'
    };
        
    
    global MongoDBDataSourceConnection() {}
    
    override global List<DataSource.Table> sync() {
        List<DataSource.Table> tables = new List<DataSource.Table>();        
        List<DataSource.Column> columns = new List<DataSource.Column>();
        
        // Always declare these two fields.
        columns.add(DataSource.Column.text('ExternalId', 255));
        columns.add(DataSource.Column.url('DisplayUrl'));
        
        columns.add(DataSource.Column.text('Description', 255));
        columns.add(DataSource.Column.text('Contract', 255));
        columns.add(DataSource.Column.text('Account', 255));
        columns.add(DataSource.Column.number('Amount', 16, 2));
        columns.add(DataSource.Column.get('CreatedDate','Created Date','', true, true, DataSource.DataType.DATETIME_TYPE, 255,0,null,null));
        
        tables.add(DataSource.Table.get('MongoDB_Invoice', 'ExternalId', columns));
        return tables;
    }
    
    // This example handles only simple SOQL. It doesn’t process
    // LIMIT, OFFSET, and it doesn’t handle
    // COUNT() queries.
    override global DataSource.TableResult query(DataSource.QueryContext c) {
        List<Map<String,Object>> rows = execQuery(getSoqlQuery(c));
        return DataSource.TableResult.get(c,rows);
    }
    
    override global List<DataSource.TableResult> search(DataSource.SearchContext c) {        
        return DataSource.SearchUtils.searchByName(c, this);
    }
    

    global override List<DataSource.UpsertResult> upsertRows(DataSource.UpsertContext context) {
        List<DataSource.UpsertResult> results = new List<DataSource.UpsertResult>();
        List<Map<String, Object>> rows = context.rows;
        Http h = new Http();
        
        for(Integer i = 0; i < rows.size(); i++){
            Map<String,Object> row = rows[i];
            HttpRequest request = new HttpRequest();
            request.setHeader('Content-Type','application/json');
            request.setTimeout(60000);

            Map<String,Object> invoice = new Map<String,Object>();
            if(String.isBlank((String)row.get('ExternalId'))){
                request.setMethod('POST');
                request.setEndpoint(DB_ENDPOINT_NC);
            }else{
                request.setMethod('PUT');
                request.setEndpoint(DB_ENDPOINT_NC+'/'+row.get('ExternalId'));
            }
            
            invoice.put('accountid', row.get('Account'));
            invoice.put('contractid', row.get('Contract'));
            invoice.put('created', row.get('CreatedDate'));
            invoice.put('amount', row.get('Amount'));
            invoice.put('description', row.get('Description'));
            
            request.setBody(JSON.serialize(invoice));
            
            HttpResponse response = h.send(request);
            
            List<Object> mList = (List<Object>)JSON.deserializeUntyped(response.getBody());
            Map<String, Object> m = (Map<String, Object>)mList[0];
            if (response.getStatusCode() == 200){
                String objId = String.valueOf(m.get('_id'));
                if(String.isBlank(objId)){
                    objId = String.valueOf(row.get('ExternalId'));
                }
                results.add(DataSource.UpsertResult.success(objId));
            } 
            else {
                results.add(DataSource.UpsertResult.failure(
                    String.valueOf(row.get('ExternalId')), 'The callout resulted in an error: ' + response.getStatusCode()+' - '+response.getBody()));
            }
        }
        return results;
    }
    
    global override List<DataSource.DeleteResult> deleteRows(DataSource.DeleteContext context) {
       List<DataSource.DeleteResult> results = new List<DataSource.DeleteResult>();
        Http h = new Http();
        
        for (String externalId : context.externalIds){
            HttpRequest request = new HttpRequest();
            request.setHeader('Content-Type','application/json');
            request.setTimeout(60000);

            request.setMethod('DELETE');
            request.setEndpoint(DB_ENDPOINT_NC+'/'+externalId);
            
            HttpResponse response = h.send(request);

            if (response.getStatusCode() == 200
                || response.getStatusCode() == 201){
                results.add(DataSource.DeleteResult.success(String.valueOf(externalId)));
            } 
            else {
                results.add(DataSource.DeleteResult.failure(
                    String.valueOf(externalId), 'The callout resulted in an error: ' + response.getStatusCode()+' - '+response.getBody()));
            }
        }
       return results;
    }

    
    private List<Map<String,Object>> execQuery(string soqlQuery) {
        List<Map<String,Object>> rows = new List<Map<String,Object>>();
        HttpRequest request = new HttpRequest();
        request.setEndpoint(DB_ENDPOINT_NC+soqlQuery);
        request.setHeader('Content-Type','application/json');
        request.setMethod('GET');
        request.setTimeout(60000);
        Http h = new Http();
        HttpResponse response = h.send(request);
        if(response.getStatusCode() != 200){ 
            return new List<Map<String,Object>>();
        }
        
        List<Object> result = (List<Object>)JSON.deserializeUntyped(response.getBody());
        for(Object obj : result){
            Map<String,Object> jsonObject = (Map<String,Object>)obj;
            Map<String,Object> row = new Map<String,Object>();
            row.put('Amount',jsonObject.get('amount'));
            row.put('Description',jsonObject.get('description'));
            row.put('Contract',jsonObject.get('contractid'));
            row.put('Account',jsonObject.get('accountid'));
            row.put('CreatedDate',parseDateTime(String.valueOf(jsonObject.get('created'))));
            row.put('ExternalId', jsonObject.get('_id'));
            row.put('DisplayUrl', DB_ENDPOINT+'/'+jsonObject.get('_id'));
            rows.add(row);
        }
        return rows;
    }
    
    private static DateTime parseDateTime(String value){
        Datetime output = null;
        if(String.isNotBlank(value)){
            try{
                output = (DateTime)JSON.deserialize('"'+value+'"', DateTime.class);
            }catch(Exception e){
                //invalid date/time
            }
        }
        return output;
    }
    
    private string getSoqlQuery(DataSource.QueryContext c) {
        string baseQuery = '?';
        string filter = getSoqlFilter('', c.tableSelection.filter);
        if (filter.length() > 0)
            baseQuery += '&query=' + EncodingUtil.urlEncode(filter, 'utf8');
        String order = getSoqlOrder(c.tableSelection.order);
        if(String.isNotBlank(order)){
            baseQuery +='&sort='+ EncodingUtil.urlEncode(order, 'utf8');
        }
        String fields = getSoqlFields(c.tableSelection.columnsSelected);
        if(String.isNotBlank(fields)){
            baseQuery +='&fields='+ EncodingUtil.urlEncode(fields, 'utf8');
        }
        return baseQuery;
    }
    
    private string getSoqlFields(List<DataSource.ColumnSelection> fieldsList) {
        if(fieldsList == null || fieldsList.size()==0) return null;
        List<String> sorts = new List<String>();
        Set<String> objFields = new Set<String>(FIELD_MAP.values());
        Map<String,Integer> fieldSelection = new Map<String,Integer>();
        for(DataSource.ColumnSelection cs : fieldsList){
            fieldSelection.put(FIELD_MAP.get(cs.columnName), 1);
        } 
        return (fieldSelection.isEmpty())?null:JSON.serialize(fieldSelection);
    }
    
    private string getSoqlOrder(List<DataSource.Order> orderList) {
        String orderBy = '';
        if(orderList == null || orderList.size()==0) return orderBy;
        List<String> sorts = new List<String>();
        for(DataSource.Order order : orderList){
            sorts.add('"'+FIELD_MAP.get(order.columnName)+'":'+((order.direction == DataSource.OrderDirection.ASCENDING)?1:-1));
        }
        if(sorts.size() >0){
            orderBy = '{'+String.join(sorts,',')+'}';
        }
        return orderBy;
    }
    private string getSoqlFilter(string query, DataSource.Filter filter) {
        if (filter == null) {
            return query;
        }
        string append;
        DataSource.FilterType type = filter.type;
        List<Map<String,Object>> retainedRows = new List<Map<String,Object>>();
        if (type == DataSource.FilterType.NOT_) {
            DataSource.Filter subfilter = filter.subfilters.get(0);
            append = '{"$not":'+getSoqlFilter('NOT', subfilter)+'}';
        } else if (type == DataSource.FilterType.AND_) {
            append =  '{"$and":'+getSoqlFilterCompound('AND', filter.subfilters)+'}';
        } else if (type == DataSource.FilterType.OR_) {
            append =  '{"$or":'+getSoqlFilterCompound('OR', filter.subfilters)+'}';
        } else {
            append = getSoqlFilterExpression(filter);
        }
        return query + append;
    }
    
    private string getSoqlFilterCompound(string op, List<DataSource.Filter> subfilters) {
        List<String> expressions = new List<String>();
        for (DataSource.Filter subfilter : subfilters) {
            expressions.add(getSoqlFilter('', subfilter));
        }
        return '['+String.join(expressions,',')+']';
    }
    
    private string getSoqlFilterExpression(DataSource.Filter filter) {
        string columnName = filter.columnName;
        string op;
        object expectedValue = filter.columnValue;
        String wrappedValue = wrapValue(expectedValue);
        if(mapColumnName(columnName) == '_id'){
            wrappedValue='{"$oid":'+wrappedValue+'}';
        }
        if (filter.type == DataSource.FilterType.EQUALS) {
            op = '{"$eq":'+wrappedValue+'}';
        } else if (filter.type == DataSource.FilterType.NOT_EQUALS) {
            op = '{"$ne":'+wrappedValue+'}';
        } else if (filter.type == DataSource.FilterType.LESS_THAN) {    
            op = '{"$lt":'+wrappedValue+'}';
        } else if (filter.type == DataSource.FilterType.GREATER_THAN) {               
            op =  '{"$gt":'+wrappedValue+'}';
        } else if (filter.type == DataSource.FilterType.LESS_THAN_OR_EQUAL_TO) {      
            op = '{"$lte":'+wrappedValue+'}';
        } else if (filter.type == DataSource.FilterType.GREATER_THAN_OR_EQUAL_TO) {              
            op = '{"$gte":'+wrappedValue+'}';
        } else if (filter.type == DataSource.FilterType.STARTS_WITH) {
            op = '{"$regex":"^'+String.valueOf(expectedValue)+'"}';
        } else if (filter.type == DataSource.FilterType.ENDS_WITH) {
            op = '{"$regex":"'+String.valueOf(expectedValue)+'$"}';
        }else if (filter.type == DataSource.FilterType.CONTAINS ) {
            op = '{"$regex":"'+String.valueOf(expectedValue)+'"}';
        } else if(filter.type == DataSource.FilterType.LIKE_ ){
            op = '{"$regex":"'+String.valueOf(expectedValue).replace('%','.*')+'"}';
        }else {
            throwException('Implementing other filter types is left as an exercise for the reader: ' + filter.type);
        }   
        return '{"'+mapColumnName(columnName) + '":' + op+'}';
    }
    
    // The standard fields ExternalId and DisplayUrl don’t exist in the
    // Account object that we are querying against, but we can generate
    // their values from the Account record ID.
    private string mapColumnName(string apexName) {
        return FIELD_MAP.get(apexName);
    }
    
    // Put strings in quotes when generating SOQL queries.
    private string wrapValue(object foundValue) {
        if(foundValue instanceof DateTime){
            return '{"$date": '+JSON.serialize(foundValue)+'}';
        }
        return JSON.serialize(foundValue);
    }
    
}
