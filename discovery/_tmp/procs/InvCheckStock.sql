/****** Object:  StoredProcedure [dbo].[InvCheckStock]    Script Date: 17/07/2026 17:09:16 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER OFF
GO
 

/****** Object:  Stored Procedure dbo.InvCheckStock    Script Date: 09/11/2005 4:56:48 PM ******/



CREATE  Procedure [dbo].[InvCheckStock]
(
      @StockId int,
      @res     int output,
      @status  int=10     
)
As
/******************************************************************************************
*  09/11/2005 dafna 
*
*******************************************************************************************/
--האם קיימת שורה בסטוק
set nocount on 
declare @MYERROR int
declare @num int

set @MYERROR=0
If @StockId<=0
   begin
     exec  @MYERROR=InvUpdateErrorMessage @StockId,@StockId,0,'Stock.ID',1,2
     set @res=0
     return @MYERROR
   end

select @res=count(*) 
from stock
where id=@StockId
and status=@status
if @res<=0
   begin
      exec  @MYERROR=InvUpdateErrorMessage @StockId,@StockId,0,'Stock.ID',1,2
   end

SET @MYERROR = @@ERROR
IF @MYERROR <> 0
  BEGIN
    set @res=0   
    RAISERROR ('PROCEDURE InvCheckStocke: 1, ERROR %d ', 19, 1,@MYERROR) WITH LOG
 return @MYERROR
  END
return @MYERROR
--exec InvCheckStock 140,0




 
GO
