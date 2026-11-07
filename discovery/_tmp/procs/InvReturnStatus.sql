/****** Object:  StoredProcedure [dbo].[InvReturnStatus]    Script Date: 17/07/2026 17:09:16 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
 

---------------------------------------
--02/11/2005 dafna with vat per item
---------------------------------------
CREATE PROCEDURE  [dbo].[InvReturnStatus]
                  @StockID    int --מספר מזהה של מסמך 
                 

as
SET TRANSACTION ISOLATION LEVEL read committed  
begin tran

DECLARE @MyError int,
        @myTranCount int  

UPDATE  JURNALTRANS 
SET JURNALTRANS.BATCHNO=9999,
JURNALTRANS.STOCKID = @STOCKID, JURNALTRANS.STATUS=1
FROM JURNALTRANS 
WHERE (((JURNALTRANS.STOCKID)=888888) AND ((JURNALTRANS.BATCHNO)=7777));


set @MyError = @@ERROR
            IF @MyError <> 0
                begin
                   set @myTranCount=@@trancount
                   while @myTranCount>0
                          begin   
                            rollback tran
                            set @myTranCount=@@trancount
                          end  
                   RAISERROR ('procedure issuedoc: InvReturnStatus , error %d ', 19, 1,@MyError) WITH LOG    
                   return @MyError  
                 end
           
commit tran
return(0)


 
GO
