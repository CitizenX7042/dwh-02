/****** Object:  StoredProcedure [dbo].[RePricingUpdate]    Script Date: 17/07/2026 17:09:16 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
 

CREATE PROCEDURE [dbo].[RePricingUpdate]
	@MY_StationID varchar(30)  -- מזהה תחנה
			
AS

SET TRANSACTION ISOLATION LEVEL READ COMMITTED   

BEGIN TRAN 

DECLARE @MyError int, 
@myTranCount int

SET @MyError=0
SET @myTranCount=0
        
UPDATE  STOCKMOVES 
SET STOCKMOVES.CURRENCYCODE = REPRICETEMPMOVES.CURRENCYCODE, 
STOCKMOVES.RATE = REPRICETEMPMOVES.RATE, 
STOCKMOVES.PRICE = REPRICETEMPMOVES.PRICE, 
STOCKMOVES.DISCOUNTPRC = REPRICETEMPMOVES.SM_DISCOUNTPRC, 
STOCKMOVES.TFTAL = REPRICETEMPMOVES.SM_TFTAL, 
STOCKMOVES.REPRICED = 1
FROM REPRICETEMPMOVES INNER JOIN STOCKMOVES 
ON REPRICETEMPMOVES.SM_ID = STOCKMOVES.ID 
WHERE ((REPRICETEMPMOVES.MOVE_UPDATED=1)
AND (REPRICETEMPMOVES.STATIONID=@MY_StationID))

SET @MyError = @@ERROR
IF @MyError <> 0
   BEGIN 
        SET @myTranCount=@@trancount
        WHILE @myTranCount>0
        BEGIN  
             rollback tran
             set @myTranCount=@@trancount
        END  
        RAISERROR ('RePricing : update_stockmoves, error %d ', 19, 1,@MyError) WITH LOG                                                                                                                      
        return @MyError  
   END
   
--6/2015 - היתה בעיה בשאילתא RePriceDocToUpdate אז החלפתי בטבלה זמנית
--*********************************************************************
CREATE TABLE #RePriceDocToUpdateNew ( StockID int )     

INSERT INTO #RePriceDocToUpdateNew ( StockID )
SELECT StockID
FROM dbo.RePriceTempMoves
WHERE (Move_Updated = 1)
AND (STATIONID = @MY_StationID)
GROUP BY StockID

DECLARE  @StockIdToUpdate int,@StockDiscPrc float

DECLARE MY_Documents_To_Update CURSOR
FOR SELECT StockID 
FROM #RePriceDocToUpdateNew

OPEN MY_Documents_To_Update

FETCH NEXT FROM MY_Documents_To_Update INTO @StockIdToUpdate

WHILE (@@fetch_status = 0)
BEGIN	
	SELECT @StockDiscPrc = DiscountPrc FROM Stock WHERE stock.id = @StockIdToUpdate
	
	EXEC @MyError=UpInvTotal @StockIdToUpdate,@StockDiscPrc,0,0,0,0

    IF @MyError <> 0
       BEGIN
             set @myTranCount=@@trancount
             while @myTranCount>0
             begin   
                  rollback tran
                  set @myTranCount=@@trancount
             end  
             RAISERROR ('RePricing : update_stocktotal, error %d ', 19, 1,@MyError) WITH LOG                                                                                                                      
             return @MyError  
       END  
       
FETCH NEXT FROM MY_Documents_To_Update INTO @StockIdToUpdate

END -- WHILE (@@fetch_status = 0)

CLOSE MY_Documents_To_Update

DEALLOCATE MY_Documents_To_Update

drop TABLE #RePriceDocToUpdateNew

--6/2015 - הוספת עדכון ליתרת תעודות משלוח של הלקוח
--***************************************************

CREATE TABLE #RePriceAccToUpdate ( AccKey varchar(15) )     

INSERT INTO #RePriceAccToUpdate ( AccKey )
SELECT AccountKey
FROM dbo.RePriceTempMoves
WHERE (Move_Updated = 1)
AND (STATIONID = @MY_StationID)
GROUP BY AccountKey

DECLARE  @AccountToUpdate varchar(15),@AssignKey varchar(15)

DECLARE MY_Accounts_To_Update CURSOR
FOR SELECT AccKey 
FROM #RePriceAccToUpdate

OPEN MY_Accounts_To_Update

FETCH NEXT FROM MY_Accounts_To_Update INTO @AccountToUpdate

WHILE (@@fetch_status = 0)
BEGIN	
	
	SELECT @AssignKey = AssignKey FROM Accounts WHERE Accounts.AccountKey = @AccountToUpdate
	
	IF @AssignKey IS NOT NULL --יש לו חשבון מרכז
	BEGIN
		SET @AccountToUpdate = @AssignKey
	END
	
	UPDATE  ACCOUNTS
	SET ACCOUNTS.OBLIGODELIVERY = (SELECT ISNULL(MAX(Round(IobligoDelivery.Delivery,2)),0) FROM IobligoDelivery  
	WHERE (IobligoDelivery.AccountKey = @AccountToUpdate)) + (SELECT  ISNULL(MAX(Round(IobligoDeliveryAssign.Delivery,2)),0) 
	FROM IobligoDeliveryAssign WHERE (IobligoDeliveryAssign.AssignKey = @AccountToUpdate))
	WHERE (ACCOUNTS.ACCOUNTKEY = @AccountToUpdate) 
	
	IF @MyError <> 0
       BEGIN
             set @myTranCount=@@trancount
             while @myTranCount>0
             begin   
                  rollback tran
                  set @myTranCount=@@trancount
             end  
             RAISERROR ('RePricing : update_Acctotal, error %d ', 19, 1,@MyError) WITH LOG                                                                                                                      
             return @MyError  
       END  
       
FETCH NEXT FROM MY_Accounts_To_Update INTO @AccountToUpdate

END -- WHILE (@@fetch_status = 0)

CLOSE MY_Accounts_To_Update

DEALLOCATE MY_Accounts_To_Update

drop TABLE #RePriceAccToUpdate

COMMIT TRAN

return 0

  
GO
