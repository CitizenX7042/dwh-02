/****** Object:  StoredProcedure [dbo].[InvIssueDocumentCh]    Script Date: 17/07/2026 17:09:16 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
 



CREATE           Procedure [dbo].[InvIssueDocumentCh]
                 @STOCKID  int,
  						   @res      int=0 output 
        
As
/*-----------------------------------------------------------------*/
/*																																 */
/*																																 */
/* (EX)InvIssueDocumentCh dafna				11/06/2005									 */
/*-----------------------------------------------------------------*/
--בדיקות לפני הפקה
declare @MYERROR int
set @MYERROR=0

set @res=0
exec  @MYERROR=chDocDates   @StockID ,@res  output

if  @res=0
    begin
      goto END_HANDLER_0
 end

set @res=0
--עדכון חשבון הכנסות או הוצאות בפריט
exec @MYERROR=UpdateMoveJurAcc   @stockID ,@res  output

if  @res=0
    begin
     --rollback tran 
     exec InvUpdateErrorMessage @STOCKID,@StockId,0,'Stock.JunalAcc',57,2   
     Return @MYERROR
 end
--העמסת עליות יבוא
declare @DocumentID int
select @DocumentID=DocumentID
from stock
where id=@stockid
If @DocumentID=53
   begin
   if (select count(*) 
       from StockMoves
		    where Stockid=@Stockid
    		and  jurnalAcc is null)>0
        set @MYERROR=@@ERROR   
        --rollback tran   

    		exec InvUpdateErrorMessage @STOCKID,@STOCKID,0,'StockMoves.JurnalAcc',55,1   
    		Return @MYERROR
   end
   
  --בדיקות תקינות לפני ההפקה  
 set @res=0
 exec  @MYERROR=ChBeforIssue @STOCKID ,@res output 
 
 if @res=0
 begin
      goto END_HANDLER_0
 end


--קבלה

if @DocumentID=2 or @DocumentID=62 or @DocumentID=87
begin
 set @res=0
 exec @MYERROR=KBchecksBeforeInv @stockid, @res output
 if @res=0
 begin
     goto END_HANDLER_0
 end

end
   
goto END_HANDLER_1

END_HANDLER_0:
if @MYERROR<>0
 goto ERR_HANDLER
else
 begin
  set @res=0
  Return @MYERROR
end

END_HANDLER_1:
if @MYERROR<>0
 goto ERR_HANDLER
else
 begin
  set @res=1
  Return @MYERROR
end

ERR_HANDLER:
if @MYERROR<>0
 begin
       RAISERROR ('PROCEDURE InvIssueDocumentCh:, ERROR %d ', 19, 1,@MYERROR) WITH LOG
       RETURN @MYERROR  
 end


GO
