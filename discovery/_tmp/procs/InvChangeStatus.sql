/****** Object:  StoredProcedure [dbo].[InvChangeStatus]    Script Date: 17/07/2026 17:09:16 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
 

-------------------------------------
--02/11/2005 dafna with vat per item 
-------------------------------------
CREATE PROCEDURE  [dbo].[InvChangeStatus]
                  @StockID    int --מספר מזהה של מסמך 
                 

as
SET TRANSACTION ISOLATION LEVEL read committed  
begin tran

DECLARE @MyError int,
        @myTranCount int  



UPDATE  JURNALTRANS
SET JURNALTRANS.STOCKID = 888888,JURNALTRANS.BATCHNO=7777,JURNALTRANS.STATUS=22
 FROM JURNALTRANS 
WHERE (((JURNALTRANS.STOCKID)=@STOCKID) AND ((JURNALTRANS.BATCHNO)=9999))


  set @MyError = @@ERROR
            IF @MyError <> 0
                begin
                   set @myTranCount=@@trancount
                   while @myTranCount>0
                          begin   
                            rollback tran
                            set @myTranCount=@@trancount
                          end  
                   RAISERROR ('procedure issuedoc: InvChangeStatus , error %d ', 19, 1,@MyError) WITH LOG    
                   return @MyError  
                 end
        
commit tran
return 0


 
GO
