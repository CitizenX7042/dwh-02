/****** Object:  StoredProcedure [dbo].[RepriceDoc]    Script Date: 17/07/2026 17:09:16 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[RepriceDoc] 
  @DocID int,
  @StationID varchar(30),
  @result     tinyint  = Null  OUTPUT     

-- return value: 0 - O.K, 1-No rate in lines, 2-No mainRate

   AS   
-- WITH ENCRYPTION

DECLARE @MYERROR INT
DECLARE @NoRate INT
DECLARE @Date DATETIME
DECLARE @MainRate float
DECLARE @VatPrc float




UPDATE  Stock
SET MainRate = RATES.RATE
FROM  COMPANYDEFENITIONS, STOCK  INNER JOIN  RATES ON (Stock.Currency = RATES.CURRENCYCODE) 
WHERE COMPANYDEFENITIONS.MAINCURRENCY<>Stock.Currency and Stock.ID = @DocID AND RATES.DATF= @Date


SET @MYERROR = @@ERROR
IF @MYERROR <> 0
  BEGIN 
   RAISERROR ('RepriceDoc: Update MainRate , error %d ', 19, 1,@MYERROR) WITH LOG    
   RETURN @MYERROR  
  END

select @Date=ValueDate, @MainRate=MainRate,@VatPrc=VatPrc 
from Stock 
where ID=@DocID

if @MainRate=0 
    Return 2

DELETE  FROM GetPrice WHERE StationID =@StationID 

SET @MYERROR = @@ERROR
IF @MYERROR <> 0
  BEGIN 
   RAISERROR ('RepriceDoc: Del GetPrice , error %d ', 19, 1,@MYERROR) WITH LOG    
   RETURN @MYERROR  
  END


INSERT INTO GetPrice ( StationID, AccountKey, ItemKey, Quantity, DatF, DocumentID, NumInfo, SMInfo,KUPANUM,BranchID )
SELECT @StationID AS Expr1, Stock.AccountKey, StockMoves.ItemKey, StockMoves.Quantity, 
Stock.ValueDate, Stock.DocumentID, StockMoves.StockID, StockMoves.ID,Stock.KUPANUM,Stock.BranchID 
FROM StockMoves INNER JOIN Stock ON StockMoves.StockID = Stock.ID
WHERE StockID = @DocID

SET @MYERROR = @@ERROR
IF @MYERROR <> 0
  BEGIN 
   RAISERROR ('RepriceDoc: Insert GetPrice, error %d ', 19, 1,@MYERROR) WITH LOG    
   RETURN @MYERROR  
  END


--הפעלת פרוצדורת שליפת מחירים

EXECUTE  GPRICE  @StationID , 0 , 1 

SET @MYERROR = @@ERROR
IF @MYERROR <> 0
  BEGIN 
   RAISERROR ('RepriceDoc: Exec GetPrice , error %d ', 19, 1,@MYERROR) WITH LOG    
   RETURN @MYERROR  
  END


INSERT INTO StockMoves ( StockID, ItemName, ItemKey, Warehouse, Agent, Reference, 
Details, DocumentID, DueDate, AlterNum, Unit, Status, CurrencyCode, Rate, Price, DiscountPrc, 
Tree, BaseMoveID, SupplyQuantity, BaseQuantity, BaseDate, SaleTaxPrc, CommisionPrc, BaseFlag, VatExampt, 
TreeFatherMoveID, Packs, SupplyPacks, CommisionPaid, Instance, BurdonOn, BurdInstance, CancelDate, 
PurchQuantity, JurnalAcc, BurdInstItemKey, ExpireDate, BranchID, ProductionID, InstanceFrom, BatchNum, 
Localization, WarrentyDate, FMPay, SourceMoveID, Quantity,vatprc,tvat,OPrice,OPriceCurrencyCode,
ODiscountPrc ,LineNoForSorting,ExtraText1,ExtraText2,ExtraSum1,ExtraSum2,GpFlag,CostCode)
SELECT StockMoves.StockID, GetPrice.TextInfo, StockMoves.ItemKey, StockMoves.Warehouse, 
StockMoves.Agent, StockMoves.Reference, StockMoves.Details, StockMoves.DocumentID, StockMoves.DueDate, 
StockMoves.AlterNum, StockMoves.Unit, StockMoves.Status, StockMoves.CurrencyCode, 
Case When StockMoves.CurrencyCode=COMPANYDEFENITIONS.MAINCURRENCY then 1 Else 0 END,
 GetPrice.Price
, GetPrice.DiscountPrc, StockMoves.Tree, StockMoves.BaseMoveID,  Case When StockMoves.Quantity>0 Then  GetPrice.Quantity
   else  GetPrice.Quantity*(-1) END,
 Case When StockMoves.Quantity>0 Then  GetPrice.Quantity
   else  GetPrice.Quantity*(-1) END
, StockMoves.BaseDate, StockMoves.SaleTaxPrc, StockMoves.CommisionPrc, 
  StockMoves.BaseFlag, StockMoves.VatExampt, StockMoves.TreeFatherMoveID, StockMoves.Packs, StockMoves.SupplyPacks,
   StockMoves.CommisionPaid, StockMoves.Instance, StockMoves.BurdonOn, StockMoves.BurdInstance, 
   StockMoves.CancelDate, Case When StockMoves.Quantity>0 Then  GetPrice.Quantity
   else  GetPrice.Quantity*(-1) END
, StockMoves.JurnalAcc, StockMoves.BurdInstItemKey, 
   StockMoves.ExpireDate, StockMoves.BranchID, StockMoves.ProductionID, StockMoves.InstanceFrom, 
   StockMoves.BatchNum, StockMoves.Localization, StockMoves.WarrentyDate, StockMoves.FMPay, 
   StockMoves.SourceMoveID, Case When StockMoves.Quantity>0 Then  GetPrice.Quantity
   else  GetPrice.Quantity*(-1) END,
 StockMoves.vatprc,stockmoves.TFtal/StockMoves.Quantity*GetPrice.Quantity*StockMoves.vatprc/100 ,
 StockMoves.OPrice,StockMoves.OPriceCurrencyCode,StockMoves.ODiscountPrc ,StockMoves.LineNoForSorting,
StockMoves.ExtraText1,StockMoves.ExtraText2,StockMoves.ExtraSum1,StockMoves.ExtraSum2,GetPrice.GpFlag,StockMoves.CostCode
FROM StockMoves INNER JOIN GetPrice ON StockMoves.ID = GetPrice.SMInfo 
inner join stock on stockmoves.StockID=stock.ID , COMPANYDEFENITIONS
WHERE (GetPrice.Quantity>0 And GetPrice.NumInfo=@DocID and GetPrice.StationID =@StationID
and stock.id=@DocID 
and StockMoves.ID in (SELECT SMInfo 
                     from GetPrice 
                     where StationID =@StationID And GetPrice.NumInfo=@DocID
                     group by SMInfo 
                     having COUNT(*)>1))

SET @MYERROR = @@ERROR
IF @MYERROR <> 0
  BEGIN 
   RAISERROR ('RepriceDoc: insert StockMoves , error %d ', 19, 1,@MYERROR) WITH LOG    
   RETURN @MYERROR  
  END


DELETE 
FROM StockMoves
FROM StockMoves INNER JOIN GetPrice ON StockMoves.ID = GetPrice.SMInfo 
WHERE (GetPrice.NumInfo=@DocID and GetPrice.StationID =@StationID
and stockMoves.Stockid=@DocID 
and StockMoves.ID in (SELECT SMInfo 
                     from GetPrice 
                     where StationID =@StationID And GetPrice.NumInfo=@DocID
                     group by SMInfo 
                     having COUNT(*)>1))

SET @MYERROR = @@ERROR
IF @MYERROR <> 0
  BEGIN 
   RAISERROR ('RepriceDoc: Del StockMoves , error %d ', 19, 1,@MYERROR) WITH LOG    
   RETURN @MYERROR  
  END


UPDATE  StockMoves
SET CurrencyCode = GetPrice.Coin,
Rate=Case When GetPrice.Coin=COMPANYDEFENITIONS.MAINCURRENCY then 1 Else 0 END,
DiscountPrc=GetPrice.DiscountPrc,CommisionPrc=GetPrice.CommisionPrc,
Price=GetPrice.Price, GPFlag=GetPrice.GPFlag
from COMPANYDEFENITIONS,GetPrice inner join stock on GetPrice.NumInfo=stock.ID
where GetPrice.StationID =@StationID and StockMoves.ID = GetPrice.SMInfo 
and StockMoves.ID not in (SELECT SMInfo 
                     from GetPrice 
                     where StationID =@StationID And GetPrice.NumInfo=@DocID
                     group by SMInfo 
                     having COUNT(*)>1)

SET @MYERROR = @@ERROR
IF @MYERROR <> 0
  BEGIN 
   RAISERROR ('RepriceDoc: Update StockMoves , error %d ', 19, 1,@MYERROR) WITH LOG    
   RETURN @MYERROR  
  END

-- עדכון שערי מט"ח

UPDATE  StockMoves
SET StockMoves.RATE = RATES.RATE
FROM  STOCKMOVES  INNER JOIN  RATES ON (StockMoves.CurrencyCode = RATES.CURRENCYCODE) 
WHERE StockID = @DocID AND RATES.DATF= @Date and StockMoves.RATE=0 

SET @MYERROR = @@ERROR
IF @MYERROR <> 0
  BEGIN 
   RAISERROR ('RepriceDoc: Update Rates , error %d ', 19, 1,@MYERROR) WITH LOG    
   RETURN @MYERROR  
  END


UPDATE StockMoves 
SET TFtal = Round(QUANTITY*PRICE*RATE*(1-DISCOUNTPrc/100) /@MainRate,2),
    TftalVat = Round(QUANTITY*PRICE*RATE*(1-DISCOUNTPrc/100) /@MainRate*(1+@VatPrc/100*(1-VatExampt)),2)  
WHERE StockID = @DocID


SET @MYERROR = @@ERROR
IF @MYERROR <> 0
  BEGIN 
   RAISERROR ('RepriceDoc: UpdateTotals , error %d ', 19, 1,@MYERROR) WITH LOG    
   RETURN @MYERROR  
  END

SELECT @NoRate=Count(*) from StockMoves where (StockID=@DocID) and (Rate=0) 

--ניקוי טבלה
DELETE  FROM GetPrice WHERE StationID =@StationID 

SET @MYERROR = @@ERROR
IF @MYERROR <> 0
  BEGIN 
   RAISERROR ('RepriceDoc: Clear GetPrice Table , error %d ', 19, 1,@MYERROR) WITH LOG    
   RETURN @MYERROR  
  END

if @NoRate=0 
  Return 0
else  
  Return 1 
  

GO
