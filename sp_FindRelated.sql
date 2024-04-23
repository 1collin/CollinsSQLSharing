/***********************************************************************************************************************
 *  
 *  sp_findRelated
 *  
 *  Stored proc to make finding related tables/views/etc. just a bit easier. 
 *  Given a string, it will search names of objects and/or optionally the names 
 *  of the columns of those objects
 *  
 *  The search string must be specified. All other parameters optional.
 * 
 *    @SearchString (NVARCHAR(128)): A substring to use as the search predicate. E.g. if you want to find all things 
 *		In-Memory OLTP, you might specify @SearchString = 'XTP'
 *  	  
 *  	  @WildcardOption (TINYINT): Specify where wildcard should be used (if any).
 *			0 => no wildcard. @SearchString is equality predicate and only exact matches returned
 *			1 => % appended to front of @SearchString
 *			2 => % appended to back of @SearchString
 *			Any other valid value => % appended to both front and back of @SearchString (default)
 *  	 	  
 *  	  @MS_ShippedOption (BIT): Include filter based on is_ms_shipped
 *			0 => WHERE is_ms_shipped = 0
 *			1 => WHERE is_ms_shipped = 1
 *			NULL => no filter for is_ms_shipped	 (default)
 *  		  
 *  	  @SearchScope (BIT): Do you want to search object names, column names, or both?  
 *  		0 => object names only
 *  		1 => column names only
 *			NULL => both object and column names (default)
 *
 *
 *	Examples:
 *
 *	EXEC sp_FindRelated 'hadr' --find all objects (ms shipped or cx created) and columns with name LIKE '%hadr%'
 *	EXEC sp_FindRelated 'XTP', @SearchScope = 1, @MS_ShippedOption = 1
 *
 *
 *	Creating in master and using sp_ms_marksystemobject makes it available in all database contexts without fully qualifying
 *  but is otherwise unnecessary. 
 *
 *  	Author: cbenkler (cbenkler@duck.com)
 *  	Last Modified: December 2022
 ***********************************************************************************************************************/

USE [master]
GO

CREATE OR ALTER PROCEDURE sp_FindRelated
(
	  @SearchString NVARCHAR(128)
	, @WildcardOption TINYINT = 3 --0: no wildcard (effectively equality); 1: % in front; 2: % in back; Any other valid value: % both sides
	, @MS_ShippedOption BIT = NULL --0/1: filter added accordingly; NULL: not filtered
	, @SearchScope BIT = NULL --0: Objects only; 1: Columns only; NULL: both
)AS
BEGIN
	SET NOCOUNT ON;
	DECLARE 
		  @SearchPH NVARCHAR(24) = '!~SEARCH_PLACEHOLDER~!'
		, @NewLine NVARCHAR(2) = NCHAR(10)+NCHAR(13)
		, @FilterMod NVARCHAR(256) = ''
	    , @ObjectQuery NVARCHAR(1024) = ''
		, @ColumnQuery NVARCHAR(1024) = ''


	SELECT @ObjectQuery = 
		'SELECT        
			   s.name [Schema]    
			, ao.name [Object]     
			, ao.type_desc [ObjectType]   
		FROM sys.schemas s    
			JOIN sys.all_objects ao ON ao.schema_id = s.schema_id    
		WHERE ao.name LIKE ' + @SearchPH 
	+ @NewLine + 'ORDER BY ao.name, ao.type_desc, s.name'

	SELECT @ColumnQuery = 
		'SELECT        
			  ac.name [Column]  
			,  t.name [ColType]      					     
			, ao.name [Object]
			,  s.name [Schema] 
			, ao.type_desc [ObjectType]  
		FROM sys.schemas s    
			JOIN sys.all_objects ao ON ao.schema_id = s.schema_id    
			JOIN sys.all_columns ac ON ac.object_id = ao.object_id  
			JOIN sys.types t ON t.user_type_id = ac.user_type_id AND t.system_type_id = ac.user_type_id   
		WHERE ac.name LIKE '+ @SearchPH 
		+ @NewLine + 'ORDER BY ac.name, ao.name, ao.type_desc, s.name'


	SELECT @FilterMod = CASE
		WHEN @WildcardOption = 0 
			THEN '''' + @SearchString + ''''
		WHEN @WildcardOption = 1 
			THEN '''%' + @SearchString + ''''
		WHEN @WildcardOption = 2
			THEN '''' + @SearchString + '%'''
		ELSE '''%' + @SearchString + '%'''
	END

	SELECT @FilterMod = CASE
		WHEN @MS_ShippedOption = 0 
			THEN @FilterMod + ' AND is_ms_shipped = 0'
		WHEN @MS_ShippedOption = 1 
			THEN @FilterMod + ' AND is_ms_shipped = 1'
		ELSE @FilterMod
	END

	IF(@SearchScope = 0 OR @SearchScope IS NULL)
	BEGIN
		SELECT @ObjectQuery = REPLACE(@ObjectQuery, @SearchPH, @FilterMod)
		SELECT 'Objects with name LIKE ' + @FilterMod + ':'
		EXEC(@ObjectQuery)
	END

	IF(@SearchScope = 1 OR @SearchScope IS NULL)
	BEGIN
		SELECT @ColumnQuery = REPLACE(@ColumnQuery, @SearchPH, @FilterMod)
		SELECT 'Columns with name LIKE ' + @FilterMod + ':'
		EXEC(@ColumnQuery)
	END
END

EXEC sp_ms_marksystemobject 'usp_FindRelated'
GO 
