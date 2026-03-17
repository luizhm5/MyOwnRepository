global with sharing class PFX_BillingReportService {

	public static String DATE_PATTERN = 'MM/dd/yyyy';
	public static Time NULL_TIME = Time.newInstance(0,0,0,0);

	public static String DT_CAMPAIGN_SPECIALIST = 'Campaign Specialist';
	public static String DT_CAMPAIGN_MANAGER = 'Campaign Manager';
	public static Set<String> DEAL_TEAM_ROLES = new Set<String>{
		DT_CAMPAIGN_SPECIALIST,
		DT_CAMPAIGN_MANAGER
	};

	public static final String BILLING_CONTACT_ROLE = 'Billing Contact';
	public static final String ACCOUNT_MANAGEMENT_ROLE = 'Account Management';
	public static final String CREATIVE_SERVICE_ROLE = 'Creative Service';
	public static final String FINANCE_MANAGER_ROLE = 'Finance Manager';
	public static final String CAMPAIGN_MANAGER_ROLE = 'Campaign Manager';

	public static final Integer PAGE_SIZE = 200;

	public static final String XLS_STRING_TYPE = 'string';
	public static final String XLS_INTEGER_TYPE = 'integer';
	public static final String XLS_DATE_TYPE = 'date';
	public static final String XLS_DATETIME_TYPE = 'datetime';
	public static final String XLS_PRICE_TYPE = 'price';
	public static final String XLS_DOLLAR_TYPE = 'dollar';

	public static final String DEFAULT_XLS_TYPE = XLS_STRING_TYPE;

	public static final String BUYING_AM_SPLIT_TYPE = 'Buying AM';

	public static final Set<String> NUMBER_FIELDS = new Set<String>();

	public static final Map<String, ValueMapper> EXPORT_COLUMNS_MAPPING_FE;

	public static final Set<String> CUMULATIVE_COLUMNS = new Set<String>{
		'Cumulative Recognized Revenue',
		'Cumulative Percent Discrepancy',
		'Cumulative Net Invoice Amount',
		'Cumulative Invoice Units',
		'Cumulative Primary Performance',
		'Cumulative Third Party Performance',
		'Cumulative Discrepancy'
	};

	private static final String Z_CYCLE = 'Z Cycle';
	private static final String NATIONAL_TYPE = Proposal_FX_ProposalService.RECTYPE_NATIONAL;

	static {
		Map<String, SObjectField> fields = Schema.PFXLineItemBilling__c.getSObjectType().getDescribe().fields.getMap();
		for (SObjectField field : fields.values()) {
			DescribeFieldResult fieldDescribe = field.getDescribe();
			if (isNumber(fieldDescribe)) {
				NUMBER_FIELDS.add(fieldDescribe.getName().toLowerCase());
			}
		}
	}

	// TODO: Move to CMN_SObjectUtils, now because of deploy
	static Boolean isNumber(DescribeFieldResult field) {
		DisplayType fieldType = field.getType();
		return fieldType == DisplayType.PERCENT
				|| field.getType() == DisplayType.CURRENCY
				|| field.getType() == DisplayType.DOUBLE;
	}

	private static ContactCache cCache;
	public static ContactCache getContactCache() {
		if (cCache == null) {
			cCache = new ContactCache();
		}
		return cCache;
	}

	private static InvoiceLineItemCache iliCache;
	public static InvoiceLineItemCache getInvoiceLineItemCache() {
		if (iliCache == null) {
			iliCache = new InvoiceLineItemCache();
		}
		return iliCache;
	}

	private static PeriodCache pCache;
	public static PeriodCache getPeriodCache() {
		if (pCache == null) {
			pCache = new PeriodCache();
		}
		return pCache;
	}

	private static SplitsCache sCache;
	public static SplitsCache getSplitsCache() {
		if (sCache == null) {
			sCache = new SplitsCache();
		}
		return sCache;
	}

	private static GeoLayerCache glCache;
	public static GeoLayerCache getGeoLayerCache() {
		if (glCache == null) {
			glCache = new GeoLayerCache();
		}
		return glCache;
	}

	private static DealTeamCache dtCache;
	public static DealTeamCache getDealTeamCache() {
		if (dtCache == null) {
			dtCache = new DealTeamCache();
		}
		return dtCache;
	}

	private static ProposalAPCache papCache;
	public static ProposalAPCache getPropApCache() {
		if (papCache == null) {
			papCache = new ProposalAPCache();
		}
		return papCache;
	}

	public with sharing class ContactCache {
		public Map<Id, Contact> billingContacts;
		public Map<Id, Contact> accMgmtContacts;
		public Map<Id, Contact> crtSrvContacts;
		public Map<Id, Contact> finMgrContacts;

		public void fillCache(Set<Id> oppIds) {
			billingContacts = new Map<Id, Contact>();
			accMgmtContacts = new Map<Id, Contact>();
			crtSrvContacts = new Map<Id, Contact>();
			finMgrContacts = new Map<Id, Contact>();
			for (Id oppId : oppIds) {
				billingContacts.put(oppId, null);
				accMgmtContacts.put(oppId, null);
				crtSrvContacts.put(oppId, null);
				finMgrContacts.put(oppId, null);
			}

			OpportunityContactRole[] contactRoles = [
					SELECT Id, OpportunityId, Contact.Id, Contact.Name, Contact.Email, Contact.MailingStreet,
							Contact.MailingPostalCode, Contact.MailingCountry, Contact.MailingCity, Contact.MailingState,
							Contact.Fax, Contact.Phone, Contact.Operative_Contact_ID__c, Role, Contact.OtherStreet, IsPrimary
					FROM OpportunityContactRole
					WHERE OpportunityId in :oppIds
			];

			for (OpportunityContactRole contactRole : contactRoles) {
				Id oppId = contactRole.OpportunityId;
				if (contactRole.Role == BILLING_CONTACT_ROLE) {
					if (contactRole.IsPrimary || !billingContacts.containsKey(oppId) || billingContacts.get(oppId) == null) {
						billingContacts.put(oppId, contactRole.Contact);
					}
				} else if (contactRole.Role == ACCOUNT_MANAGEMENT_ROLE) {
					accMgmtContacts.put(oppId, contactRole.Contact);
				} else if (contactRole.Role == CREATIVE_SERVICE_ROLE) {
					crtSrvContacts.put(oppId, contactRole.Contact);
				} else if (contactRole.Role == FINANCE_MANAGER_ROLE) {
					finMgrContacts.put(oppId, contactRole.Contact);
				}
			}
		}
	}

	public with sharing class InvoiceLineItemCache {
		Set<Id> liBillingIds;
		Map<Id, Decimal> invLINetInvoiceAmtCache;
		Map<Id, Decimal> invLIInvoicedUnitsCache;
		Map<Id, Decimal> invLI1stPartyUtsCache;
		Map<Id, Decimal> invLI3rdPartyUtsCache;

		Map<Id, Decimal> recognizedValue;
		Map<Id, Integer> liBillingIdToOperativeId;

		Integer CUM_REC_REVENUE_INDEX = EXPORT_COLUMNS.indexOf('Cumulative Recognized Revenue');
		Integer CUM_PREC_DISCREP_INDEX = EXPORT_COLUMNS.indexOf('Cumulative Percent Discrepancy');
		Integer CUM_NET_INV_AMT_INDEX = EXPORT_COLUMNS.indexOf('Cumulative Net Invoice Amount');
		Integer CUM_INV_UTS_INDEX = EXPORT_COLUMNS.indexOf('Cumulative Invoice Units');
		Integer CUM_PRIM_PERF_INDEX = EXPORT_COLUMNS.indexOf('Cumulative Primary Performance');
		Integer CUM_3RD_PARTY_PERF_INDEX = EXPORT_COLUMNS.indexOf('Cumulative Third Party Performance');
		Integer CUM_DISCREP_INDEX = EXPORT_COLUMNS.indexOf('Cumulative Discrepancy');

		public void fillCache(Set<Id> liBillingIds) {
			this.liBillingIds = liBillingIds;

			invLINetInvoiceAmtCache = new Map<Id, Decimal>();
			invLIInvoicedUnitsCache = new Map<Id, Decimal>();
			invLI1stPartyUtsCache = new Map<Id, Decimal>();
			invLI3rdPartyUtsCache = new Map<Id, Decimal>();
			recognizedValue = new Map<Id, Decimal>();
			liBillingIdToOperativeId = new Map<Id, Integer>();

			for (Id liBillingId : liBillingIds) {
				invLINetInvoiceAmtCache.put(liBillingId, 0);
				invLIInvoicedUnitsCache.put(liBillingId, 0);
				invLI1stPartyUtsCache.put(liBillingId, 0);
				invLI3rdPartyUtsCache.put(liBillingId, 0);
			}

			Map<Id, PFXLineItemBilling__c> liBillings = new Map<Id, PFXLineItemBilling__c>([
				SELECT Id, LineItemID__c, OrderBilling__r.Proposal__c, BillingPeriod__c,
					LineItemID__r.ProductionCostmethod__c, LineItemID__r.Product__r.Cost_Method__c,
					InvoiceUnits__c, LineItemID__r.ContractUnitPrice__c, BillingPeriod__r.PeriodDate__c,
					Operative_ID_Formula__c
				FROM PFXLineItemBilling__c
				WHERE Id in :liBillingIds AND Inactive__c = false
			]);

			Set<Id> ppIds = new Set<Id>(), pIds = new Set<Id>(), periodIds = new Set<Id>();

			for (PFXLineItemBilling__c liBilling : liBillings.values()) {
				ppIds.add(liBilling.LineItemID__c);
				pIds.add(liBilling.OrderBilling__r.Proposal__c);
				periodIds.add(liBilling.BillingPeriod__c);
				liBillingIdToOperativeId.put(liBilling.Id, Integer.valueOf(liBilling.Operative_ID_Formula__c));
			}

			PFXLineItemBilling__c[] cumulatives = [
				SELECT LineItemID__c, InvoiceUnits__c, NetBillingAmount__c, FirstPartyUnits__c, ThirdPartyUnits__c, BillingPeriod__r.PeriodDate__c,
					RemainingAmount__c, RemainingUnits__c
				FROM PFXLineItemBilling__c
				WHERE LineItemID__c in :ppIds AND Inactive__c = false
				ORDER BY BillingPeriod__r.PeriodDate__c ASC
			];

			Map<Id, PFXLineItemBilling__c[]> cumulativesByPP = new Map<Id, PFXLineItemBilling__c[]>();
			for (Id ppId : ppIds) {
				cumulativesByPP.put(ppId, new PFXLineItemBilling__c[]{});
			}
			for (PFXLineItemBilling__c cumulative : cumulatives) {
				cumulativesByPP.get(cumulative.LineItemID__c).add(cumulative);
			}

			for (PFXLineItemBilling__c liBilling : liBillings.values()) {
				Map<String, Decimal> params = getParams(liBilling, cumulativesByPP.get(liBilling.LineItemID__c));
				invLINetInvoiceAmtCache.put(liBilling.Id, params.get('netInvAmt'));
				invLIInvoicedUnitsCache.put(liBilling.Id, params.get('cumInvUts'));
				invLI1stPartyUtsCache.put(liBilling.Id, params.get('cumFstPrf'));
				invLI3rdPartyUtsCache.put(liBilling.Id, params.get('cum3rdPrt'));
				recognizedValue.put(liBilling.Id, params.get('recognizedValue'));
			}
		}

		public Map<String, Decimal> getParams(PFXLineItemBilling__c record, PFXLineItemBilling__c[] productRecords) {
			Decimal netInvAmt = 0, cumInvUts = 0, cumFstPrf = 0, cum3rdPrt = 0, recognizedValue = 0;
			Integer index = 0;
			Integer size = productRecords.size();
			while (index < size && record.BillingPeriod__r.PeriodDate__c >= productRecords[index].BillingPeriod__r.PeriodDate__c) {
				netInvAmt += (productRecords[index].NetBillingAmount__c == null ? 0 : productRecords[index].NetBillingAmount__c);
				recognizedValue += (productRecords[index].NetBillingAmount__c == null ? 0 : productRecords[index].NetBillingAmount__c);
				cumInvUts += (productRecords[index].InvoiceUnits__c == null ? 0 : productRecords[index].InvoiceUnits__c);
				cumFstPrf += (productRecords[index].FirstPartyUnits__c == null ? 0 : productRecords[index].FirstPartyUnits__c);
				cum3rdPrt += (productRecords[index].ThirdPartyUnits__c == null ? 0 : productRecords[index].ThirdPartyUnits__c);
				index++;
			}
			return new Map<String, Decimal>{
				'netInvAmt' => netInvAmt,
				'cumInvUts' => cumInvUts,
				'cumFstPrf' => cumFstPrf,
				'cum3rdPrt' => cum3rdPrt,
				'recognizedValue' => recognizedValue
			};
		}

		public Map<String, Object> getCumulutiveInfo() {
			Map<String, Object> result = new Map<String, Object>();

			for (Id liBillingId : liBillingIds) {
				Map<Integer, Object> row = new Map<Integer, Object>();
				row.put(CUM_PREC_DISCREP_INDEX, getDiscrepancy(invLI1stPartyUtsCache.get(liBillingId), invLI3rdPartyUtsCache.get(liBillingId)));
				row.put(CUM_NET_INV_AMT_INDEX, invLINetInvoiceAmtCache.get(liBillingId));
				row.put(CUM_INV_UTS_INDEX, invLIInvoicedUnitsCache.get(liBillingId));
				row.put(CUM_PRIM_PERF_INDEX, invLI1stPartyUtsCache.get(liBillingId));
				row.put(CUM_3RD_PARTY_PERF_INDEX, invLI3rdPartyUtsCache.get(liBillingId));
				row.put(CUM_DISCREP_INDEX, invLI1stPartyUtsCache.get(liBillingId) - invLI3rdPartyUtsCache.get(liBillingId));
				row.put(CUM_REC_REVENUE_INDEX, recognizedValue.get(liBillingId));
				result.put(liBillingId, row);
			}
			return result;
		}

		public Decimal getDiscrepancy(Decimal firstParty, Decimal thirdParty) {
			return firstParty == 0 ? 0 : (firstParty - thirdParty) / firstParty;
		}

		public void updateFinExportCumulativeInfo(Map<String, Object> cumulativeInfos) {
			OP1_Fin_Export__c[] finExpRows = new OP1_Fin_Export__c[]{};
			for (Id liBillingId:cumulativeInfos.keySet()) {
				Integer operativeId = liBillingIdToOperativeId.get(liBillingId);
				Map<Integer, Object> cumulativeInfo = (Map<Integer, Object>)cumulativeInfos.get(liBillingId);
				OP1_Fin_Export__c finExportRow = new OP1_Fin_Export__c(
					LineInvoiceId__c = operativeId,
					Cumulative_Discrepancy__c = (Decimal)cumulativeInfo.get(CUM_DISCREP_INDEX),
					Cumulative_Invoice_Units__c = (Decimal)cumulativeInfo.get(CUM_INV_UTS_INDEX),
					Cumulative_Net_Invoice_Amount__c = (Decimal)cumulativeInfo.get(CUM_NET_INV_AMT_INDEX),
					Cumulative_Percent_Discrepancy__c = (Decimal)cumulativeInfo.get(CUM_PREC_DISCREP_INDEX),
					Cumulative_Primary_Performance__c = (Decimal)cumulativeInfo.get(CUM_PRIM_PERF_INDEX),
					Cumulative_Recognized_Revenue__c = (Decimal)cumulativeInfo.get(CUM_REC_REVENUE_INDEX),
					Cumulative_Third_Party_Performance__c = (Decimal)cumulativeInfo.get(CUM_3RD_PARTY_PERF_INDEX),
					ProcessingStatus__c = null
				);
				finExpRows.add(finExportRow);
			}
			upsert finExpRows LineInvoiceId__c;
		}
	}

	public class PeriodCache {
		Map<Id, Decimal> periodGrossSumCache;

		public void fillCache(PFXLineItemBilling__c[] items) {
			periodGrossSumCache = new Map<Id, Decimal>();

			for (PFXLineItemBilling__c item : items) {
				Id pId = item.BillingPeriod__c;
				if (!periodGrossSumCache.containsKey(pId)) {
					periodGrossSumCache.put(pId, 0);
				}
				if (item.GrossAmount__c != null) {
					periodGrossSumCache.put(pId, periodGrossSumCache.get(pId) + item.GrossAmount__c);
				}
			}
		}
	}

	public with sharing class GeoLayerCache {
		public Map<Id, Integer> glWeatherTriggerNumberCache;

		public void fillCache(Set<Id> ppIds) {
			glWeatherTriggerNumberCache = new Map<Id, Integer>();

			for (Id ppId : ppIds) {
				glWeatherTriggerNumberCache.put(ppId, 0);
			}

			Geo_Layers__c[] weatherTriggeringGLs = [
					SELECT Id, Proposal_Products__c
					FROM Geo_Layers__c
					WHERE Proposal_Products__c in :ppIds AND CustomPackageChildProduct__c = null
					AND (TargetOptions__r.Mapped_Value_CD__c like '%wfxtg%' OR TargetOptions__r.Mapped_Value_CD__c like '%сxtg%')
			];

			for (Geo_Layers__c wtgl : weatherTriggeringGLs) {
				Id ppId = wtgl.Proposal_Products__c;
				glWeatherTriggerNumberCache.put(ppId, glWeatherTriggerNumberCache.get(ppId) + 1);
			}
		}
	}

	public with sharing class SplitsCache {
		private Map<Id, Decimal> ownerSplitsPercentCache;
		private Map<Id, Set<String>> secondarySplits;

		public void fillCache(Set<Id> oppIds) {
			ownerSplitsPercentCache = new Map<Id, Decimal>();
			secondarySplits = new Map<Id, Set<String>>();

			for (Id oppId : oppIds) {
				ownerSplitsPercentCache.put(oppId, 0);
				secondarySplits.put(oppId, new Set<String>());
			}

			Opportunity_Splits__c[] splits = [
					SELECT Id, Split_Partner__c, Split_Percent__c, Opportunity__r.OwnerId, Opportunity__c, Split_Type__c, Split_Partner__r.Name
					FROM Opportunity_Splits__c
					WHERE Opportunity__c in :oppIds
			];

			for (Opportunity_Splits__c split : splits) {
				Id oppId = split.Opportunity__c;
				if (split.Split_Partner__c == split.Opportunity__r.OwnerId && split.Split_Percent__c != null) {
					ownerSplitsPercentCache.put(oppId, ownerSplitsPercentCache.get(oppId) + split.Split_Percent__c);
				}

				if (split.Split_Partner__c != split.Opportunity__r.OwnerId) {
					secondarySplits.get(oppId).add(split.Split_Partner__r.Name);
				}
			}
		}
	}

	public with sharing class DealTeamCache {
		public Map<Id, OpportunityTeamMember[]> oppIdToMembers;

		public void fillCache(Set<Id> oppIds) {
			oppIdToMembers = new Map<Id, OpportunityTeamMember[]>();

			for (Id oppId : oppIds) {
				oppIdToMembers.put(oppId, new OpportunityTeamMember[]{});
			}

			OpportunityTeamMember[] oppMembers = [
				SELECT Id, OpportunityId, TeamMemberRole, User.Name, Category__c
				FROM OpportunityTeamMember
				WHERE OpportunityId in :oppIds
			];

			for (OpportunityTeamMember oppMember : oppMembers) {
				oppIdToMembers.get(oppMember.OpportunityId).add(oppMember);
			}
		}
	}

	public with sharing class ProposalAPCache {
		public Map<Id, Boolean> isMinOrderMap;

		public void fillCache(Set<Id> pIds) {
			isMinOrderMap = new Map<Id, Boolean>();
			for (Id pId : pIds) {
				isMinOrderMap.put(pId, false);
			}

			PFX_Approval_Process__c[] minOrderAPs = [
				SELECT Id, Proposal_ID__c
				FROM PFX_Approval_Process__c
				WHERE Proposal_ID__c in :pIds AND Type__c = :Proposal_FX_ApprovalStatus.PFX_APPROVAL_TYPE_MIN_ORDER_AMT
			];

			for (PFX_Approval_Process__c ap : minOrderAPs) {
				isMinOrderMap.put(ap.Proposal_ID__c, true);
			}
		}
	}

	public interface MappingLogic {
		Object getValue(PFXLineItemBilling__c record);
	}

	public class OrderIdMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			if (rec.LineItemID__r.Proposal__r.Operative_Order_Id__c != null) {
				return rec.LineItemID__r.Proposal__r.Operative_Order_Id__c;
			}
			return '';
		}
	}

	public class OrderIdMapperFE implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			if (rec.LineItemID__r.Proposal__r.Operative_Order_Id__c != null) {
				return Decimal.valueOf(rec.LineItemID__r.Proposal__r.Operative_Order_Id__c);
			}
			return null;
		}
	}

	public class InvoiceIdMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Operative_Invoice_ID__c; }
	}

	public class InvoiceIdMapperFE implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			return rec.OrderBilling__r.Operative_Invoice_ID__c == null ? null : Decimal.valueOf(rec.OrderBilling__r.Operative_Invoice_ID__c);
		}
	}

	public class LineInvoiceIdMapperFE implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			return rec.Operative_ID_Formula__c;
		}
	}

	public class OrderNameMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.LineItemID__r.Proposal__r.Name; }
	}

	public class PrimarySPMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			String sellerId = String.isBlank(rec.OrderBilling__r.Proposal__r.Opportunity__r.Owner.Seller_ID_1__c)
				? 'NO_SELLER_ID'
				: rec.OrderBilling__r.Proposal__r.Opportunity__r.Owner.Seller_ID_1__c;
			Decimal percent = getSplitsCache().ownerSplitsPercentCache.get(rec.LineItemID__r.Proposal__r.Opportunity__c);
			return rec.LineItemID__r.Proposal__r.Opportunity__r.Owner.Name + '^' + sellerId + '^ ' + percent + '%';
		}
	}

	public class InvoiceNameMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.BillingName__c; }
	}

	public class AgencyDscMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.AgencyDiscount__c == null ? 0 : rec.AgencyDiscount__c; }
	}

	public class NetInvAmtMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			Decimal discount = (rec.AgencyDiscount__c != null ? rec.AgencyDiscount__c : 0) / 100.0;
			return (rec.GrossAmount__c != null ? rec.GrossAmount__c : 0) * (1 - discount);
		}
	}

	public class PeriodNameMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.BillingPeriod__r.Billing_Start_Date__c; }
	}

	public class PeriodNameMapperFE implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			return CMN_DateUtils.formatGMT(
					rec.BillingPeriod__r.Billing_Start_Date__c,
					XLS_TYPES_EXPORT_COLUMNS.get('Billing Period Name')
			);
		}
	}

	public class PeriodIdMapperFE implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.BillingPeriod__c; }
	}

	public class StartDateMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.BillingPeriod__r.Billing_Start_Date__c; }
	}

	public class EndDateMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.BillingPeriod__r.Billing_End_Date__c; }
	}

	public class LINameIdMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.LineItemID__r.Product__r.ProductID__c; }
	}

	public class LINameIdMapperFE implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			if (rec.LineItemID__r.Product__r.ProductID__c == null) {
				return null;
			}
			return Decimal.valueOf(rec.LineItemID__r.Product__r.ProductID__c);
		}
	}

	public class LINameMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			String prefix = String.isNotBlank(rec.LineItemID__r.PrefixName__c) ? rec.LineItemID__r.PrefixName__c + '_' : '';
			String lineName = rec.LineItemID__r.Line_Item_Name__c;
			String suffix = String.isNotBlank(rec.LineItemID__r.Line_Name_With_Top_TOs_UserPart__c) ? '_' + rec.LineItemID__r.Line_Name_With_Top_TOs_UserPart__c : '';
			return prefix + lineName + suffix;
		}
	}

	public class LIStartDateMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.LineStartDate__c == null ? null : rec.LineStartDate__c.formatGmt(DATE_PATTERN); }
	}

	public class LIStartDateMapperFE implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.LineStartDate__c; }
	}

	public class LIEndDateMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.LineEndDate__c == null ? null : rec.LineEndDate__c.formatGmt(DATE_PATTERN); }
	}

	public class LIEndDateMapperFE implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.LineEndDate__c; }
	}

	public class LICostMethodMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			return !String.isEmpty(rec.LineItemID__r.ProductionCostMethod__c)
				? rec.LineItemID__r.ProductionCostMethod__c
				: rec.LineItemID__r.Product__r.Cost_Method__c;
		}
	}

	public class UnitTypeMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			String cm = !String.isEmpty(rec.LineItemID__r.ProductionCostMethod__c)
				? rec.LineItemID__r.ProductionCostMethod__c
				: rec.LineItemID__r.Product__r.Cost_Method__c;
			if (cm != null) {
				switch on cm.toLowerCase() {
					when 'cpm' {
						return 'Impressions';
					}
					when 'cpa' {
						return 'Actions';
					}
					when 'cpc' {
						return 'Clicks';
					}
					when 'cost per day' {
						return 'Days';
					}
					when 'flat rate' {
						return 'Flat';
					}
					when else {
						return 'Unknown';
					}
				}
			}
			return 'Unknown';
		}
	}

	public class LIImpressionsMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.LineContractQuantity__c; }
	}

	public class LICUPMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.BillingRate__c; }
	}

	public class NetLIUnitCost implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			if (rec.BillingRate__c == null) {
				return 'CPM not specified';
			}
			Decimal discount = (rec.AgencyDiscount__c != null ? rec.AgencyDiscount__c : 0) / 100.0;
			return (rec.BillingRate__c != null ? rec.BillingRate__c : 0) * (1 - discount);
		}
	}

	public class BillAccIdMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.BillingAccount__r.IBM_Billing_ID__c; }
	}

	public class BillingStreetMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.BillingAccount__r.BillingStreet; }
	}

	public class BillingStreet2Mapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.BillingAccount__r.ShippingStreet; }
	}

	public class BillingCityMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.BillingAccount__r.BillingCity; }
	}

	public class BillingCountryMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.BillingAccount__r.BillingCountry; }
	}

	public class CreditStatusMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.BillingAccount__r.Operative_Credit_Status__c; }
	}

	public class AccountIdMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.BillingAccount__r.Operative_Account_Id__c; }
	}

	public class AccountIdMapperFE implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			if (rec.OrderBilling__r.Proposal__r.BillingAccount__r.Operative_Account_Id__c == null) {
				return null;
			}
			return Decimal.valueOf(rec.OrderBilling__r.Proposal__r.BillingAccount__r.Operative_Account_Id__c);
		}
	}

	public class AccountNameMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.BillingAccount__r.Name; }
	}

	public class AccountPhoneMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.BillingAccount__r.Phone; }
	}

	public class BillingStateMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.BillingAccount__r.BillingState; }
	}

	public class BillingZipMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.BillingAccount__r.BillingPostalCode; }
	}

	public class BCNameMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			Contact bc = getContactCache().billingContacts.get(rec.OrderBilling__r.Proposal__r.Opportunity__c);
			if (bc == null) {
				return null;
			}
			return bc.Name;
		}
	}

	public class BCStreetMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			Contact bc = getContactCache().billingContacts.get(rec.OrderBilling__r.Proposal__r.Opportunity__c);
			if (bc == null) {
				return null;
			}
			return bc.MailingStreet;
		}
	}

	public class BCStreet2Mapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			Contact bc = getContactCache().billingContacts.get(rec.OrderBilling__r.Proposal__r.Opportunity__c);
			if (bc == null) {
				return null;
			}
			return bc.OtherStreet;
		}
	}

	public class BCCityMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			Contact bc = getContactCache().billingContacts.get(rec.OrderBilling__r.Proposal__r.Opportunity__c);
			if (bc == null) {
				return null;
			}
			return bc.MailingCity;
		}
	}

	public class BCCountryMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			Contact bc = getContactCache().billingContacts.get(rec.OrderBilling__r.Proposal__r.Opportunity__c);
			if (bc == null) {
				return null;
			}
			return bc.MailingCountry;
		}
	}

	public class BCFaxMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			Contact bc = getContactCache().billingContacts.get(rec.OrderBilling__r.Proposal__r.Opportunity__c);
			if (bc == null) {
				return null;
			}
			return bc.Fax;
		}
	}

	public class BCIdMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			Contact bc = getContactCache().billingContacts.get(rec.OrderBilling__r.Proposal__r.Opportunity__c);
			if (bc == null) {
				return null;
			}
			return bc.Operative_Contact_ID__c;
		}
	}

	public class BCIdMapperFE implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			Contact bc = getContactCache().billingContacts.get(rec.OrderBilling__r.Proposal__r.Opportunity__c);
			if (bc == null || bc.Operative_Contact_ID__c == null) {
				return null;
			}
			return Decimal.valueOf(bc.Operative_Contact_ID__c);
		}
	}

	public class BCPhoneMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			Contact bc = getContactCache().billingContacts.get(rec.OrderBilling__r.Proposal__r.Opportunity__c);
			if (bc == null) {
				return null;
			}
			return bc.Phone;
		}
	}

	public class BCStateMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			Contact bc = getContactCache().billingContacts.get(rec.OrderBilling__r.Proposal__r.Opportunity__c);
			if (bc == null) {
				return null;
			}
			return bc.MailingState;
		}
	}

	public class BCZipMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			Contact bc = getContactCache().billingContacts.get(rec.OrderBilling__r.Proposal__r.Opportunity__c);
			if (bc == null) {
				return null;
			}
			return bc.MailingPostalCode;
		}
	}

	public class BCEmailMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			Contact bc = getContactCache().billingContacts.get(rec.OrderBilling__r.Proposal__r.Opportunity__c);
			if (bc == null) {
				return null;
			}
			return bc.Email;
		}
	}

	public class BTermsNameMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.BillingTerms__c; }
	}

	public class UnrRevMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			Decimal grossLICost = rec.LineContractTotalGross__c != null ? rec.LineContractTotalGross__c : 0;
			Decimal netInvAmt = rec.CumulativeNetAmount__c != null ? rec.CumulativeNetAmount__c : 0;
			Decimal result = grossLICost - netInvAmt;
			return result;
		}
	}

	public class BTermsIdMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			switch on rec.OrderBilling__r.Proposal__r.BillingTerms__c {
				when 'Net 30' {
					return '1';
				}
				when 'Net 45' {
					return '2';
				}
				when 'Net 60' {
					return '3';
				}
				when 'Net 90' {
					return '4';
				}
				when 'Prepay' {
					return '5';
				}
				when else {
					return '';
				}
			}
		}
	}

	public class DiscrepAmtMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			Decimal fp = rec.FirstPartyUnits__c == null ? 0 : rec.FirstPartyUnits__c;
			Decimal tp = rec.ThirdPartyUnits__c == null ? 0 : rec.ThirdPartyUnits__c;
			return fp - tp;
		}
	}

	public class PONumberMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.AMAC_General_5__c; }
	}

	public class TotalLICostMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.LineContractTotalGross__c; }
	}

	public class SumGrossMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			return getPeriodCache().periodGrossSumCache.get(rec.BillingPeriod__c);
		}
	}

	public class HardCodeMapper implements MappingLogic {
		private Object value;
		public HardCodeMapper(Object value) {
			this.value = value;
		}
		public Object getValue(PFXLineItemBilling__c rec) { return value; }
	}

	public static Boolean isManualChangedByType(PFXLineItemBilling__c rec, String type) {
		if (type == 'units') {
			return rec.InvoiceUnitsChangedManually__c;
		} else if (type == 'amount') {
			return rec.InvoiceAmountChangedManually__c;
		} else if (type == 'both') {
			return rec.InvoiceUnitsChangedManually__c || rec.InvoiceAmountChangedManually__c;
		}
		return false;
	}

	public class InvAmountMapper implements MappingLogic {
		private String type;
		public InvAmountMapper(String type) {
			this.type = type;
		}
		public Object getValue(PFXLineItemBilling__c rec) {
			if (rec.BillingSource__c == 'DFP') {
				return 'Primary Performance';
			} else if (isManualChangedByType(rec, type)) {
				return 'Manual Entry';
			}
			return '3rd Party Performance';
		}
	}

	public class AIUTSMapper implements MappingLogic {
		private String type;
		public AIUTSMapper(String type) {
			this.type = type;
		}
		public Object getValue(PFXLineItemBilling__c rec) {
			if (isManualChangedByType(rec, type)) {
				return 'Finance Override';
			}
			return 'Invoice Schedule';
		}
	}

	public class ActRevRecTermSourceMapper implements MappingLogic {
		private String type;
		public ActRevRecTermSourceMapper(String type) {
			this.type = type;
		}
		public Object getValue(PFXLineItemBilling__c rec) {
			String ppBs = rec.LineItemID__r.BillingSource__c,
				liBs = rec.BillingSource__c;
			if (ppBs == liBs) {
				return 'Invoice Org Setting';
			}
			return 'Finance Override';
		}
	}

	public class ActRevRecTermUsedMapper implements MappingLogic {
		private String type;
		public ActRevRecTermUsedMapper(String type) {
			this.type = type;
		}
		public Object getValue(PFXLineItemBilling__c rec) {
			String ppBs = rec.LineItemID__r.BillingSource__c,
				liBs = rec.BillingSource__c;
			if (liBs == ppBs) {
				return 'Invoiced';
			}
			return 'Manual Entry';
		}
	}

	public class ANIAAmtTermsSourceMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			if (rec.LineItemID__r.ActualInvoiceUnitsTermSource__c == 'Invoice Schedule') {
				return 'Invoice Org Setting';
			} else if (rec.LineItemID__r.ActualInvoiceUnitsTermSource__c == 'Finance Override') {
				return 'Finance Override';
			}
			return '';
		}
	}

	public class IsLastMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			return (rec.LineEndDate__c != null
				&& (rec.OrderBilling__r.Billing_Start_Date__c == null || rec.OrderBilling__r.Billing_Start_Date__c <= rec.LineEndDate__c.dateGmt())
				&& (rec.OrderBilling__r.Billing_End_Date__c == null || rec.OrderBilling__r.Billing_End_Date__c >= rec.LineEndDate__c.dateGmt())) ? 'YES' : 'NO';
		}
	}

	public class BookingTypeMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.LineItemID__r.Product__r.Default_Booking_Type__c; }
	}

	public class AdTypeMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.LineItemID__r.Product__r.Ad_Type__c; }
	}

	public class AdvPlNameMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.LineItemID__r.Advertiser_Placement_Name__c; }
	}

	public class LINotesMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.LineItemID__r.Notes__c; }
	}

	public class IsNetworkMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return String.valueOf(rec.LineItemID__r.Proposal__r.Network__c); }
	}

	public class IsNetworkMapperFE implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.LineItemID__r.Proposal__r.Network__c; }
	}

	public class IsPreEmptibleMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return String.valueOf(rec.LineItemID__r.Product__r.Default_Booking_Type__c == 'pre-emptible' || rec.LineItemID__r.Product__r.Default_Booking_Type__c == 'preemptible'); }
	}

	public class IsPreEmptibleMapperFE implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.LineItemID__r.Product__r.Default_Booking_Type__c == 'pre-emptible' || rec.LineItemID__r.Product__r.Default_Booking_Type__c == 'preemptible'; }
	}

	public class IsVideoMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return String.valueOf(rec.LineItemID__r.Line_Name__c != null && (rec.LineItemID__r.Line_Name__c.containsIgnoreCase('pre-roll') || rec.LineItemID__r.Line_Name__c.containsIgnoreCase('preroll'))); }
	}

	public class IsVideoMapperFE implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.LineItemID__r.Line_Name__c != null && (rec.LineItemID__r.Line_Name__c.containsIgnoreCase('pre-roll') || rec.LineItemID__r.Line_Name__c.containsIgnoreCase('preroll')); }
	}

	public class NoChReasonMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.LineItemID__r.NoChargeReason__c; }
	}

	public class MakeGoodAmtMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			Decimal result = rec.LineItemID__r.MakeGood__c ? rec.LineItemID__r.MakeGoodAmount__c : 0;
			return result;
		}
	}

	public class CleanStateAmtMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			Decimal result = rec.LineItemID__r.CleanSlate__c ? rec.LineItemID__r.CleanSlateAmount__c : 0;
			return result;
		}
	}

	public class EfCancDateMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.EffectiveCancellationDate__c; }
	}

	public class CancelAmtMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			Decimal result = !String.isBlank(rec.LineItemID__r.CancelledSystems__c) ? rec.LineItemID__r.CancellationAmount__c : 0;
			return result;
		}
	}

	public class CancelDtlsMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.CancellationDetails__c; }
	}

	public class AVMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			Decimal result = rec.LineItemID__r.Added_Value_Boolean__c ? rec.LineItemID__r.Added_Value__c : 0;
			return result;
		}
	}

	public class IsWeatherTriggeringMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			Integer wtGeoLayers = getGeoLayerCache().glWeatherTriggerNumberCache.get(rec.LineItemID__c);
			return String.valueOf(wtGeoLayers > 0);
		}
	}

	public class IsWeatherTriggeringMapperFE implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			Integer wtGeoLayers = getGeoLayerCache().glWeatherTriggerNumberCache.get(rec.LineItemID__c);
			return wtGeoLayers > 0;
		}
	}

	public class SurveyMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return String.valueOf(rec.LineItemID__r.Product__r.Name != null && rec.LineItemID__r.Product__r.Name.containsIgnoreCase('survey')); }
	}

	public class SurveyMapperFE implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.LineItemID__r.Product__r.Name != null && rec.LineItemID__r.Product__r.Name.containsIgnoreCase('survey'); }
	}

	public class IsHouseMApper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return String.valueOf(rec.LineItemID__r.Line_Name__c != null && rec.LineItemID__r.Line_Name__c.containsIgnoreCase('house')); }
	}

	public class IsHouseMApperFE implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.LineItemID__r.Line_Name__c != null && rec.LineItemID__r.Line_Name__c.containsIgnoreCase('house'); }
	}

	public class CancelledMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return String.valueOf(!String.isBlank(rec.LineItemID__r.CancelledSystems__c)); }
	}

	public class CancelledMapperFE implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return !String.isBlank(rec.LineItemID__r.CancelledSystems__c); }
	}

	public class IsAVMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return String.valueOf(rec.LineItemID__r.Added_Value_Boolean__c); }
	}

	public class IsAVMapperFE implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.LineItemID__r.Added_Value_Boolean__c; }
	}

	public class CleantSlateMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return String.valueOf(rec.LineItemID__r.CleanSlate__c); }
	}

	public class CleantSlateMapperFE implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.LineItemID__r.CleanSlate__c; }
	}

	public class GroupSectionIdMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.LineItemID__r.ProposalProductGroup__r.LineItemSectionID__c; }
	}

	public class GroupSectionIdMapperFE implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			if (rec.LineItemID__r.ProposalProductGroup__r.LineItemSectionID__c == null) {
				return null;
			}
			return Decimal.valueOf(rec.LineItemID__r.ProposalProductGroup__r.LineItemSectionID__c);
		}
	}

	public class GroupNameMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.LineItemID__r.ProposalProductGroup__r.Name; }
	}

	public class LIOrderMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.LineItemID__r.OrderNumber__c; }
	}

	public class MakeGoodMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.LineItemID__r.MakeGood__c ? 'Yes' : 'No'; }
	}

	public class LINetCostMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.LineContractTotalNet__c; }
	}

	public class OrderNetCostMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.NetValue__c; }
	}

	public class LICurrencyMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.LineItemID__r.CurrencyIsoCode; }
	}

	public class OrderActionQuantity implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.LineItemID__r.DFPActions__c; }
	}

	public class TotalClicksMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.ClicksSum__c; }
	}

	public class TotalGrossCostMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.Total_Budget__c; }
	}

	private static Map<String, String> INVOICE_REVIEW_STATUS_MAP = new Map<String, String>{
		null => 'None',
		'No Status' => 'None',
		'Hold' => 'On Hold',
		'Audited' => 'Pending Final Review',
		'Audited-Data' => 'Pending Final Review',
		'In Progress' => 'None',
		'Invoiced' => 'Pending Final Review',
		'Revised' => 'Pending Final Review'
	};
	public class InvRevStatusMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			return INVOICE_REVIEW_STATUS_MAP.get(rec.OrderBilling__r.BillingStatus__c);
		}
	}

	public class OrderCurrencyMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.OrderCurrency__c; }
	}

	public class MeasurStudyFndgMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.MeasurementStudyFundingSource__c; }
	}

	public class VerticalMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.Vertical__c; }
	}

	public class RestrAgAdvMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return String.valueOf(rec.OrderBilling__r.Proposal__r.Opportunity__r.Account.Agency_Caution_List__c); }
	}

	public class RestrAgAdvMapperFE implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.Opportunity__r.Account.Agency_Caution_List__c; }
	}

	public class SecKPIMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.Opportunity__r.Secondary_Validation_Goal_KPI__c; }
	}

	public class PrKPIMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.Opportunity__r.Primary_Measurement_Goal_KPI__c; }
	}

	public class PGMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.ProgrammaticGuaranteed__c; }
	}

	public class InViewDtlsMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			String[] values = new String[]{};
			if (String.isNotBlank(rec.OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.AMAC_Viewability_1__c)) {
				values.add(rec.OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.AMAC_Viewability_1__c);
			}
			if (String.isNotBlank(rec.OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.AMAC_Viewability_6__c)) {
				values.add(rec.OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.AMAC_Viewability_6__c);
			}
			if (String.isNotBlank(rec.OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.AMAC_Viewability_9__c)) {
				values.add(rec.OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.AMAC_Viewability_9__c);
			}
			return String.join(values, ' ');
		}
	}

	public class InViewBlngMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.AMAC_Viewability_1__c; }
	}

	public class AnalystNtsMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			String result = rec.OrderBilling__r.Proposal__r.AnalystNotes__c;
			if (result == null) {
				return '';
			}
			String[] nonEmptyParts = new String[]{};
			String[] parts = rec.OrderBilling__r.Proposal__r.AnalystNotes__c.split(',');
			for (String part : parts) {
				part = part.trim();
				if (String.isNotBlank(part)) {
					nonEmptyParts.add(part);
				}
			}
			return String.join(nonEmptyParts, ',');
		}
	}

	public class BillingNotesMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			String result = rec.OrderBilling__r.Proposal__r.BillingNotes__c;
			if (result == null) {
				return '';
			}
			String[] nonEmptyParts = new String[]{};
			String[] parts = rec.OrderBilling__r.Proposal__r.BillingNotes__c.split(',');
			for (String part : parts) {
				part = part.trim();
				if (String.isNotBlank(part)) {
					nonEmptyParts.add(part);
				}
			}
			return String.join(nonEmptyParts, ',');
		}
	}

	public class BillingPswdMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.BillingPassword__c; }
	}

	public class BillingUsnmMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.BillingUsername__c; }
	}

	public class DoNotBillMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return String.valueOf(rec.OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.DoNotBill__c); }
	}

	public class DoNotBillMapperFE implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.DoNotBill__c; }
	}

	public class PaymentTypeMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.Payment_Type__c; }
	}

	public class PayingFeesMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.PayingFees__c; }
	}

	public class MinOrdMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			return getPropApCache().isMinOrderMap.get(rec.OrderBilling__r.Proposal__c) ? 'Minimum Order' : 'None';
		}
	}

	public class OrderEDMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.End_Date__c; }
	}

	public class OrderImprMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.Total_Impressions__c; }
	}

	public class OrderStageMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.Stage__c; }
	}

	public class OrderSDMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.Start_Date__c; }
	}

	public class PercDiscrepMapp implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			if (rec.ThirdPartyUnits__c == null || rec.FirstPartyUnits__c == null || rec.FirstPartyUnits__c == 0) {
				return 0.0;
			}
			return 100.0 - (rec.ThirdPartyUnits__c * 100 / rec.FirstPartyUnits__c);
		}
	}

	public class OPNameMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.LineItemID__r.Product__r.Name; }
	}

	public static Decimal calcRecogRevenue(String cm, Decimal calculated, Decimal rate, Decimal agencyDiscount) {
		rate = (rate == null ? 0 : rate);
		calculated = calculated == null || calculated < 0 ? 0 : calculated;
		Decimal grossAmt = 0;
		if (cm == 'cpm') {
			grossAmt = calculated.divide(1000, 6, System.RoundingMode.UP) * rate;
		} else {
			grossAmt = calculated * rate;
		}
		Decimal netAmount = grossAmt * (1 - (agencyDiscount == null ? 0 : agencyDiscount) / 100);
		return netAmount < 0 ? 0 : netAmount;
	}

	public class RecogRevMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			String cm = !String.isEmpty(rec.LineItemID__r.ProductionCostMethod__c)
				? rec.LineItemID__r.ProductionCostMethod__c
				: rec.LineItemID__r.Product__r.Cost_Method__c;
			Decimal netAmount = 0;
			if (cm != null) {
				netAmount = calcRecogRevenue(cm, rec.CalculatedUnits__c, rec.BillingRate__c == null ? rec.LineItemID__r.ContractUnitPrice__c : rec.BillingRate__c, rec.AgencyDiscount__c);
			}
			return netAmount < 0 ? 0 : netAmount;
		}
	}

	public class PrimProdSystemMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			if (Proposal_FX_TextUtils.multiPickListContains(rec.LineItemID__r.ProductionSystems__c, 'DFP')) {
				return 'Weather - DFP Premium';
			}
			return rec.LineItemID__r.ProductionSystems__c;
		}
	}

	public class ThrdPrtProdSysMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			if (rec.BillingSource__c == 'DFP') {
				return '';
			}
			return rec.BillingSource__c;
		}
	}

	public class LIIdMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.LineItemID__r.Operative_Order_LineID__c; }
	}

	public class LIIdMapperFE implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			return rec.LineItemID__r.Operative_Order_LineID__c == null ? null : Decimal.valueOf(rec.LineItemID__r.Operative_Order_LineID__c);
		}
	}

	public class OrdAltIdMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.AMAC_General_3__c; }
	}

	public class PrimAdvertiserMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.Opportunity__r.Account.Name; }
	}

	public class BAgencyMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.OrderBilling__r.Proposal__r.Opportunity__r.Buying_Agency__r.Name; }
	}

	public class GlobalMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { return rec.LineItemID__r.CurrencyIsoCode == 'USD' ? 'Domestic' : 'intl'; }
	}

	public class AddlPersonMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			Set<String> addls = getSplitsCache().secondarySplits.get(rec.OrderBilling__r.Proposal__r.Opportunity__c);
			return String.join((Iterable<String>) addls, ';');
		}
	}

	public class PlannerMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			Contact actMgmtContact = getContactCache().accMgmtContacts.get(rec.OrderBilling__r.Proposal__r.Opportunity__c);
			return actMgmtContact != null ? actMgmtContact.Name : '';
		}
	}

	public class CampaignManagersMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			Id oppId = rec.OrderBilling__r.Proposal__r.Opportunity__c;
			Set<String> specs = new Set<String>();
			if (oppId != null) {
				for (OpportunityTeamMember member : getDealTeamCache().oppIdToMembers.get(oppId)) {
					if (member.TeamMemberRole == DT_CAMPAIGN_MANAGER) {
						specs.add(member.User.Name);
					}
				}
			}
			String[] specsArray = new String[]{};
			specsArray.addAll(specs);
			return String.join(specsArray, ', ');
		}
	}

	public class OrderPrimaryTeamMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			Id oppId = rec.OrderBilling__r.Proposal__r.Opportunity__c;
			Set<String> categories = new Set<String>();
			if (oppId != null) {
				for (OpportunityTeamMember member : getDealTeamCache().oppIdToMembers.get(oppId)) {
					categories.add(member.Category__c);
				}
			}
			String[] categoriesArray = new String[]{};
			categoriesArray.addAll(categories);
			return String.join(categoriesArray, ', ');
		}
	}

	public class WatcherMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			OpportunityTeamMember[] members = getDealTeamCache().oppIdToMembers.get(rec.OrderBilling__r.Proposal__r.Opportunity__c);
			Set<String> memberNames = new Set<String>();
			for (OpportunityTeamMember member : members) {
				memberNames.add(member.User.Name);
			}
			return String.join((Iterable<String>)memberNames, ';');
		}
	}

	public class CrtSrvRepMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			Contact actMgmtContact = getContactCache().crtSrvContacts.get(rec.OrderBilling__r.Proposal__r.Opportunity__c);
			return actMgmtContact != null ? actMgmtContact.Name : '';
		}
	}

	public class FinMgrMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			Contact actMgmtContact = getContactCache().finMgrContacts.get(rec.OrderBilling__r.Proposal__r.Opportunity__c);
			return actMgmtContact != null ? actMgmtContact.Name : '';
		}
	}

	public class PrimTraffikerMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) {
			Id oppId = rec.OrderBilling__r.Proposal__r.Opportunity__c;
			Set<String> specs = new Set<String>();
			if (oppId != null) {
				for (OpportunityTeamMember member : getDealTeamCache().oppIdToMembers.get(oppId)) {
					if (member.TeamMemberRole == DT_CAMPAIGN_SPECIALIST) {
						specs.add(member.User.Name);
					}
				}
			}
			String[] specsArray = new String[]{};
			specsArray.addAll(specs);
			return String.join(specsArray, ', ');
		}
	}

	public class SoldToCMRMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { 
			return rec.OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.BillingAccount__r.IBM_Billing_ID__c; 
		}
	}

	public class SoldToMPPMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { 
			return rec.OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.BillingAccount__r.Phy_NS_Address_ID__c; 
		}
	}

	public class BillToCMRMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { 
			String returnValue = rec.OrderBilling__r.Proposal__r.Opportunity__r.SoldToAccount__r.IBM_Billing_ID__c;
			
			if(String.isBlank(returnValue)){
				returnValue = rec.OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.BillingAccount__r.IBM_Billing_ID__c;
			}

			return returnValue; 
		}
	}

	public class BillToMPPMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { 
			String returnValue = rec.OrderBilling__r.Proposal__r.Opportunity__r.SoldToAccount__r.Mail_NS_Address_ID__c;
			
			if(String.isBlank(returnValue)){
				returnValue = rec.OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.BillingAccount__r.Mail_NS_Address_ID__c;
			}

			return returnValue; 
		
		}
	}

	public class ShipToCMRMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { 
			return rec.OrderBilling__r.Proposal__r.Opportunity__r.Account.IBM_Billing_ID__c;
		}
	}

	public class ShipToMPPMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { 
			return rec.OrderBilling__r.Proposal__r.Opportunity__r.Account.Phy_NS_Address_ID__c;
		}
	}

	public class EmailMPOCMapper implements MappingLogic {
		public Object getValue(PFXLineItemBilling__c rec) { 
			return rec.OrderBilling__r.Proposal__r.Opportunity__r.SendInvoiceToMainContact__c ? 'true' : ''; 
		}
	}

	public class ValueMapper {

		String[] fields;
		MappingLogic logic;

		public ValueMapper(String field) {
			this.fields = new String[]{field.toLowerCase()};
		}

		public ValueMapper(String field, MappingLogic logic) {
			this.fields = new String[]{field.toLowerCase()};
			this.logic = logic;
		}

		public ValueMapper(String[] fields, MappingLogic logic) {
			this.fields = fields;
			this.logic = logic;
		}

		public Object getValue(PFXLineItemBilling__c record) {
			if (logic == null) {
				return getValue(record, fields[0]);
			}
			return logic.getValue(record);
		}

		public String[] getFields() {
			return this.fields;
		}

		private Object getValue(SObject record, String field) {
			if (String.isBlank(field)) {
				return '-';
			}
			Object result = record.get(field);
			if (result == null && NUMBER_FIELDS.contains(field)) {
				return 0;
			}
			return result;
		}
	}

	public static final String[] EXPORT_COLUMNS = new String[]{
		'Order ID',
		'Invoice ID',
		'Order Name',
		'Invoice Name',
		'Gross Invoice Amount',
		'Net Invoice Amount',
		'Agency Discount Percentage',
		'Primary Salesperson',
		'Billing Period Name',
		'Billing Period Start Date',
		'Billing Period End Date',
		'Line Item ID',
		'Line Item Name',
		'Line Item Start Date',
		'Line Item End Date',
		'Line Item Cost Method',
		'Line Item Quantity',
		'Line Item Unit Cost Before Discounts',
		'Gross Line Item Unit Cost',
		'Net Line Item Unit Cost',
		'Unit Type',
		'Invoice Units',
		'Primary Performance',
		'Third Party Performance',
		'Billing Account - Billing ID',
		'Billing Account Address 1',
		'Billing Account Address 2',
		'Billing Account City',
		'Billing Account Country',
		'Billing Account Credit Status',
		'Billing Account Email',
		'Billing Account ID',
		'Billing Account Name',
		'Billing Account Phone',
		'Billing Account State/Province/Region',
		'Billing Account Zip/Postal_Code',
		'Billing Contact',
		'Billing Contact Address 1',
		'Billing Contact Address 2',
		'Billing Contact City',
		'Billing Contact Country',
		'Billing Contact Fax',
		'Billing Contact ID',
		'Billing Contact Phone',
		'Billing Contact State/Province/Region',
		'Billing Contact Zip',
		'Billing Contact Email',
		'Billing Period Scheme Name',
		'Billing Terms ID',
		'Billing Terms Name',
		'Unrecognized Revenue',
		'Discrepancy Amount',
		'External PO number',
		'Gross Line Item Cost',
		'Gross Order Cost',
		'Invoice Amount without discounts',
		'Invoice Review Status',
		'Invoice Schedule - Suggested Invoice Amount',
		'Invoice Schedule - Suggested Invoice Amount Terms',
		'Invoice Schedule - Suggested Invoice Unit Terms',
		'Invoice Schedule - Suggested Invoice Units',
		'Actual Invoice Units Term Source',
		'Actual Invoice Units Term Used',
		'Actual Net Invoice Amount Term Source',
		'Actual Revenue Recognition Term Source',
		'Actual Net Invoice Amount Term Used',
		'Actual Revenue Recognition Term Used',
		'Cumulative Percent Discrepancy',
		'Invoice Version',
		'Cumulative Net Invoice Amount',
		'Cumulative Invoice Units',
		'Cumulative Primary Performance',
		'Cumulative Third Party Performance',
		'Cumulative Discrepancy',
		'Invoicing Organization Name',
		'Invoicing Organization Type',
		'Last Billing Period',
		'Line Item Booking Type',
		'Opportunity Cost Amount',
		'Revenue Ad Type',
		'Ad Type',
		'Platform Percentages',
		'Reporting Notes',
		'Advertiser Placement Name',
		'Line Item Notes',
		'Comp Opportunity',
		'Network',
		'National Preempt',
		'Video',
		'Creative Type',
		'Additional Third Party Billing Source',
		'Solbright LI ID',
		'Solbright Campaign ID',
		'Cancel Reason Code',
		'Makegood Amount',
		'Clean Slate Amount',
		'Cancellation Amount',
		'Added Value Amount',
		'Weather Triggering',
		'Survey OOB',
		'Preemptible',
		'House',
		'Cancelled',
		'Added Value',
		'Clean Slate',
		'No Charge Reason Code',
		'Line Item Revenue Recognition Type',
		'Line Item Section ID',
		'Line Item Section Name',
		'Line Item Sort Order',
		'Makegood',
		'Net Line Item Cost',
		'Net Order Cost',
		'Network Based Currency',
		'Order Action Quantity',
		'Order Click Quantity',
		'Order Cost without discounts',
		'Order Currency',
		'Measurement Study Funding Source',
		'Vertical',
		'Secondary Benchmark',
		'Primary Benchmark',
		'Secondary KPI',
		'Primary KPI',
		'Automated Guaranteed',
		'In-View Details',
		'In-View Billing',
		'Billing Analyst Notes',
		'Billable Source Vendor Name',
		'Billing Notes',
		'Billing Password',
		'Billing Username',
		'Cancellation does not comply with terms',
		'Industry Segment',
		'# of invoices',
		'Restricted Agency/Advertiser',
		'Do Not Bill',
		'Payment Type',
		'Paying Fees',
		'Order Size',
		'Inside Sales',
		'Solbright IO Number',
		'Solbright Contract ID',
		'Effective Cancellation Date',
		'Client Segmentation',
		'Cancellation Amount',
		'Cancellation Details',
		'Order End Date',
		'Order Impression Quantity',
		'Order Owner',
		'Order Placement Quantity',
		'Order Primary Team',
		'Order Sales Stage',
		'Order Start Date',
		'Parent Line Item ID',
		'Percent Discrepancy',
		'Primary Production System',
		'Product ID',
		'Commission Setting',
		'Product Name',
		'Ratecard',
		'Recognized Revenue',
		'Remaining Amount',
		'Remaining Units',
		'Third Party Production System',
		'Total Line Item Discount Percentage',
		'Cumulative Recognized Revenue',
		'Invoice Schedule - Cumulative Suggested Invoice Amount',
		'Invoice Schedule - Cumulative Suggested Invoice Units',
		'Order Alternate ID',
		'Product Tags',
		'Invoice Assigned To',
		'Primary Advertiser',
		'Second Advertiser',
		'Buying Agency',
		'Creative Agency',
		'Other Partner',
		'Rich Media Partner',
		'Billing Partner',
		'Broker',
		'Third Party',
		'Planning Agency',
		'Other Partner',
		'Billing Partner',
		'Third Party',
		'VAT Registration Number',
		'General Notes',
		'Inside Sales',
		'Credit Check Amount',
		'Credit Check',
		'Accounting Notes',
		'Global',
		'Additional Salesperson',
		'Planner',
		'Ad Ops Consultant',
		'Watcher',
		'Creative Service Rep',
		'Finance Mgr',
		'Primary Trafficker',
		'Sold To Billing Id',
		'Sold To NetSuite Id',
		'Bill To Billing Id',
		'Bill To NetSuite Id',
		'Ship To Billing Id',
		'Ship To NetSuite Id',
		'Email MPOC'
	};

	public static final Set<String> CUMULATIVE_FIELDS = new Set<String>{
		'Cumulative Percent Discrepancy',
		'Cumulative Net Invoice Amount',
		'Cumulative Invoice Units',
		'Cumulative Primary Performance',
		'Cumulative Third Party Performance',
		'Cumulative Discrepancy',
		'Cumulative Recognized Revenue'
	};

	public static final Map<String, String> XLS_TYPES_EXPORT_COLUMNS = new Map<String, String>{
		'Cumulative Percent Discrepancy' => '0.0000',
		'Net Line Item Unit Cost' => '0.00',
		'Billing Period Name' => 'MM-YYYY',
		'Billing Period Start Date' => 'MM/DD/YYYY',
		'Billing Period End Date' => 'MM/DD/YYYY',
		'Order End Date' => 'MM/DD/YYYY',
		'Order Start Date' => 'MM/DD/YYYY',
		'Gross Invoice Amount' => '0.0000',
		'Effective Cancellation Date' => 'MM/DD/YYYY',
		'Order ID' => 'number',
		'Invoice ID' => 'number',
		'Net Invoice Amount' => '0.0000',
		'Line Item Unit Cost Before Discounts' => '0.0000',
		'Gross Line Item Unit Cost' => '0.0000',
		'Unrecognized Revenue' => '0.0000',
		'Agency Discount Percentage' => '0.0000',
		'Line Item Quantity' => 'number',
		'Invoice Units' => 'number',
		'Primary Performance' => 'number',
		'Third Party Performance' => 'number',
		'Billing Terms ID' => 'number',
		'Discrepancy Amount' => 'number',
		'Invoice Amount without discounts' => '0.0000',
		'Gross Line Item Cost' => '0.0000',
		'Gross Order Cost' => '0.0000',
		'Invoice Schedule - Suggested Invoice Units' => 'number',
		'Cumulative Net Invoice Amount' => '0.0000',
		'Cumulative Invoice Units' => 'number',
		'Cumulative Primary Performance' => 'number',
		'Cumulative Third Party Performance' => 'number',
		'Cumulative Discrepancy' => 'number',
		'Makegood Amount' => '0.0000',
		'Cancellation Amount' => '0.0000',
		'Clean Slate Amount' => '0.0000',
		'Added Value Amount' => '0.0000',
		'Line Item Sort Order' => 'number',
		'Net Line Item Cost' => '0.0000',
		'Net Order Cost' => '0.0000',
		'Order Click Quantity' => 'number',
		'Order Cost without discounts' => '0.0000',
		'Order Impression Quantity' => 'number',
		'Percent Discrepancy' => '0.0000',
		'Recognized Revenue' => '0.0000',
		'Remaining Amount' => '0.0000',
		'Line Item Section ID' => 'number',
		'Remaining Units' => 'number',
		'Solbright IO Number' => 'number',
		'Solbright Contract ID' => 'number',
		'Order Placement Quantity' => 'number',
		'Invoice Schedule - Cumulative Suggested Invoice Amount' => 'number',
		'Invoice Schedule - Cumulative Suggested Invoice Units' => 'number'
		// define non-string xls types
	};

	public static final Map<String, ValueMapper> EXPORT_COLUMNS_MAPPING = new Map<String, ValueMapper>{
		'Order ID' => new ValueMapper('LineItemID__r.Proposal__r.Operative_Order_Id__c', new OrderIdMapper()),
		'Invoice ID' => new ValueMapper('OrderBilling__r.Operative_Invoice_ID__c', new InvoiceIdMapper()),
		'Line Invoice ID' => new ValueMapper('Operative_ID_Formula__c', new HardCodeMapper('')),
		'Order Name' => new ValueMapper('LineItemID__r.Proposal__r.Name', new OrderNameMapper()),
		'Invoice Name' => new ValueMapper('OrderBilling__r.BillingName__c', new InvoiceNameMapper()),
		'Gross Invoice Amount' => new ValueMapper('GrossAmount__c'),
		'Net Invoice Amount' => new ValueMapper(new String[]{'GrossAmount__c', 'AgencyDiscount__c'}, new NetInvAmtMapper()),
		'Agency Discount Percentage' => new ValueMapper('OrderBilling__r.Proposal__r.AgencyDiscount__c', new AgencyDscMapper()),
		'Primary Salesperson' => new ValueMapper(new String[]{'LineItemID__r.Proposal__r.Opportunity__r.OwnerId', 'LineItemID__r.Proposal__r.Opportunity__r.Owner.Name', 'OrderBilling__r.Proposal__r.Opportunity__r.Owner.Seller_ID_1__c'}, new PrimarySPMapper()),
		'Billing Period Name' => new ValueMapper('BillingPeriod__r.Billing_Start_Date__c', new PeriodNameMapper()),
		'Billing Period Start Date' => new ValueMapper('BillingPeriod__r.Billing_Start_Date__c', new StartDateMapper()),
		'Billing Period End Date' => new ValueMapper('BillingPeriod__r.Billing_End_Date__c', new EndDateMapper()),
		'Line Item ID' => new ValueMapper('LineItemID__r.Operative_Order_LineID__c', new LIIdMapper()),
		'Line Item Name' => new ValueMapper(new String[]{
				'LineItemID__r.Line_Item_Name__c',
				'LineItemID__r.PrefixName__c',
				'LineItemID__r.Line_Name_With_Top_TOs_UserPart__c'
		}, new LINameMapper()),
		'Line Item Start Date' => new ValueMapper('LineStartDate__c', new LIStartDateMapper()),
		'Line Item End Date' => new ValueMapper('LineEndDate__c', new LIEndDateMapper()),
		'Line Item Cost Method' => new ValueMapper(new String[]{'LineItemID__r.ProductionCostMethod__c','LineItemID__r.Product__r.Cost_Method__c'}, new LICostMethodMapper()),
		'Line Item Quantity' => new ValueMapper('LineContractQuantity__c', new LIImpressionsMapper()),
		'Line Item Unit Cost Before Discounts' => new ValueMapper('BillingRate__c', new LICUPMapper()),
		'Gross Line Item Unit Cost' => new ValueMapper('BillingRate__c', new LICUPMapper()),
		'Net Line Item Unit Cost' => new ValueMapper(new String[]{'AgencyDiscount__c', 'BillingRate__c'}, new NetLIUnitCost()),
		'Unit Type' => new ValueMapper(new String[]{'LineItemID__r.ProductionCostMethod__c','LineItemID__r.Product__r.Cost_Method__c'}, new UnitTypeMapper()),
		'Invoice Units' => new ValueMapper('InvoiceUnits__c'),
		'Primary Performance' => new ValueMapper('FirstPartyUnits__c'),
		'Third Party Performance' => new ValueMapper('ThirdPartyUnits__c'),
		'Billing Account - Billing ID' => new ValueMapper('OrderBilling__r.Proposal__r.BillingAccount__r.IBM_Billing_ID__c', new BillAccIdMapper()),
		'Billing Account Address 1' => new ValueMapper('OrderBilling__r.Proposal__r.BillingAccount__r.BillingStreet', new BillingStreetMapper()),
		'Billing Account Address 2' => new ValueMapper('OrderBilling__r.Proposal__r.BillingAccount__r.ShippingStreet', new BillingStreet2Mapper()),
		'Billing Account City' => new ValueMapper('OrderBilling__r.Proposal__r.BillingAccount__r.BillingCity', new BillingCityMapper()),
		'Billing Account Country' => new ValueMapper('OrderBilling__r.Proposal__r.BillingAccount__r.BillingCountry', new BillingCountryMapper()),
		'Billing Account Credit Status' => new ValueMapper('OrderBilling__r.Proposal__r.BillingAccount__r.Operative_Credit_Status__c', new CreditStatusMapper()),
		'Billing Account Email' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__c', new BCEmailMapper()),
		'Billing Account ID' => new ValueMapper('OrderBilling__r.Proposal__r.BillingAccount__r.Operative_Account_Id__c', new AccountIdMapper()),
		'Billing Account Name' => new ValueMapper('OrderBilling__r.Proposal__r.BillingAccount__r.Name', new AccountNameMapper()),
		'Billing Account Phone' => new ValueMapper('OrderBilling__r.Proposal__r.BillingAccount__r.Phone', new AccountPhoneMapper()),
		'Billing Account State/Province/Region' => new ValueMapper('OrderBilling__r.Proposal__r.BillingAccount__r.BillingState', new BillingStateMapper()),
		'Billing Account Zip/Postal_Code' => new ValueMapper('OrderBilling__r.Proposal__r.BillingAccount__r.BillingPostalCode', new BillingZipMapper()),
		'Billing Contact' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__c', new BCNameMapper()),
		'Billing Contact Address 1' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__c', new BCStreetMapper()),
		'Billing Contact Address 2' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__c', new BCStreet2Mapper()),
		'Billing Contact City' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__c', new BCCityMapper()),
		'Billing Contact Country' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__c', new BCCountryMapper()),
		'Billing Contact Fax' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__c', new BCFaxMapper()),
		'Billing Contact ID' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__c', new BCIdMapper()),
		'Billing Contact Phone' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__c', new BCPhoneMapper()),
		'Billing Contact State/Province/Region' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__c', new BCStateMapper()),
		'Billing Contact Zip' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__c', new BCZipMapper()),
		'Billing Contact Email' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__c', new BCEmailMapper()),
		'Billing Period Scheme Name' => new ValueMapper('', new HardCodeMapper('Calendar Year')),
		'Billing Terms ID' => new ValueMapper('toLabel(OrderBilling__r.Proposal__r.BillingTerms__c)', new BTermsIdMapper()),
		'Billing Terms Name' => new ValueMapper('toLabel(OrderBilling__r.Proposal__r.BillingTerms__c)', new BTermsNameMapper()),
		'Unrecognized Revenue' => new ValueMapper(new String[]{'LineContractTotalGross__c','CumulativeNetAmount__c'}, new UnrRevMapper()),
		'Discrepancy Amount' => new ValueMapper(new String[]{'FirstPartyUnits__c', 'ThirdPartyUnits__c'}, new DiscrepAmtMapper()),
		'External PO number' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.AMAC_General_5__c', new PONumberMapper()),
		'Gross Line Item Cost' => new ValueMapper('LineContractTotalGross__c', new TotalLICostMapper()), // Q / 1000 * T, Q -  Line Item Quantity, T - Net Line Item Unit Cost
		'Gross Order Cost' => new ValueMapper('OrderBilling__r.Proposal__r.Total_Budget__c', new TotalGrossCostMapper()),
		'Invoice Amount without discounts' => new ValueMapper('GrossAmount__c'),
		'Invoice Review Status' => new ValueMapper('OrderBilling__r.BillingStatus__c', new InvRevStatusMapper()),
		'Invoice Schedule - Suggested Invoice Amount' => new ValueMapper('', new HardCodeMapper('0')),
		'Invoice Schedule - Suggested Invoice Amount Terms' => new ValueMapper(new String[]{'BillingSource__c','InvoiceAmountChangedManually__c','InvoiceUnitsChangedManually__c'}, new InvAmountMapper('both')),
		'Invoice Schedule - Suggested Invoice Unit Terms' => new ValueMapper(new String[]{'BillingSource__c','InvoiceAmountChangedManually__c','InvoiceUnitsChangedManually__c'}, new InvAmountMapper('both')),
		'Invoice Schedule - Suggested Invoice Units' => new ValueMapper('', new HardCodeMapper('0')),
		'Actual Invoice Units Term Source' => new ValueMapper(new String[]{'BillingSource__c','InvoiceAmountChangedManually__c','InvoiceUnitsChangedManually__c'}, new AIUTSMapper('units')),
		'Actual Invoice Units Term Used' => new ValueMapper(new String[]{'BillingSource__c','InvoiceAmountChangedManually__c','InvoiceUnitsChangedManually__c'}, new InvAmountMapper('units')),
		'Actual Net Invoice Amount Term Source' => new ValueMapper(new String[]{'BillingSource__c','InvoiceAmountChangedManually__c','InvoiceUnitsChangedManually__c'}, new AIUTSMapper('amount')),
		'Actual Revenue Recognition Term Source' =>  new ValueMapper(new String[]{'LineItemID__r.BillingSource__c', 'BillingSource__c'}, new ActRevRecTermSourceMapper('amount')),
		'Actual Net Invoice Amount Term Used' => new ValueMapper(new String[]{'BillingSource__c','InvoiceAmountChangedManually__c','InvoiceUnitsChangedManually__c'}, new InvAmountMapper('both')),
		'Actual Revenue Recognition Term Used' => new ValueMapper(new String[]{'LineItemID__r.BillingSource__c', 'BillingSource__c'}, new ActRevRecTermUsedMapper('amount')),
		'Cumulative Percent Discrepancy' => new ValueMapper('Id'),
		'Invoice Version' => new ValueMapper('', new HardCodeMapper('')),
		'Cumulative Net Invoice Amount' => new ValueMapper('Id'),
		'Cumulative Invoice Units' => new ValueMapper('Id'),
		'Cumulative Primary Performance' => new ValueMapper('Id'),
		'Cumulative Third Party Performance' => new ValueMapper('Id'),
		'Cumulative Discrepancy' => new ValueMapper('Id'),
		'Invoicing Organization Name' => new ValueMapper('', new HardCodeMapper('The Weather Channel Companies')),
		'Invoicing Organization Type' => new ValueMapper('', new HardCodeMapper('Global Organization')),
		'Last Billing Period' => new ValueMapper(new String[]{'LineEndDate__c', 'OrderBilling__r.Billing_Start_Date__c', 'OrderBilling__r.Billing_End_Date__c'}, new IsLastMapper()),
		'Line Item Booking Type' => new ValueMapper('LineItemID__r.Product__r.Default_Booking_Type__c', new BookingTypeMapper()),
		'Opportunity Cost Amount' => new ValueMapper(''), // TODO: ???
		'Revenue Ad Type' => new ValueMapper('LineItemID__r.Product__r.Ad_Type__c', new AdTypeMapper()),
		'Ad Type' => new ValueMapper('LineItemID__r.Product__r.Ad_Type__c', new AdTypeMapper()),
		'Platform Percentages' => new ValueMapper('', new HardCodeMapper('')),
		'Reporting Notes' => new ValueMapper('', new HardCodeMapper('')),
		'Advertiser Placement Name' => new ValueMapper('LineItemID__r.Advertiser_Placement_Name__c', new AdvPlNameMapper()),
		'Line Item Notes' => new ValueMapper('LineItemID__r.Notes__c', new LINotesMapper()),
		'Comp Opportunity' => new ValueMapper('', new HardCodeMapper('')),
		'Network' => new ValueMapper('LineItemID__r.Proposal__r.Network__c', new IsNetworkMapper()),
		'National Preempt' => new ValueMapper('LineItemID__r.Product__r.Default_Booking_Type__c', new IsPreEmptibleMapper()),
		'Video' => new ValueMapper('LineItemID__r.Line_Name__c', new IsVideoMapper()),
		'Creative Type' => new ValueMapper('', new HardCodeMapper('')),
		'Additional Third Party Billing Source' => new ValueMapper(''), // TODO: what field?
		'Solbright LI ID' => new ValueMapper('', new HardCodeMapper('')),
		'Solbright Campaign ID' => new ValueMapper('', new HardCodeMapper('')),
		'Cancel Reason Code' => new ValueMapper('LineItemID__r.NoChargeReason__c', new NoChReasonMapper()),
		'Makegood Amount' => new ValueMapper(new String[]{'LineItemID__r.MakeGood__c', 'LineItemID__r.MakeGoodAmount__c'}, new MakeGoodAmtMapper()),
		'Clean Slate Amount' => new ValueMapper(new String[]{'LineItemID__r.CleanSlate__c', 'LineItemID__r.CleanSlateAmount__c'}, new CleanStateAmtMapper()),
		'Cancellation Amount' => new ValueMapper(new String[]{'LineItemID__r.CancellationAmount__c', 'LineItemID__r.CancelledSystems__c'}, new CancelAmtMapper()),
		'Added Value Amount' => new ValueMapper(new String[]{'LineItemID__r.Added_Value__c', 'LineItemID__r.Added_Value_Boolean__c'}, new AVMapper()),
		'Weather Triggering' => new ValueMapper('LineItemID__c', new IsWeatherTriggeringMapper()),
		'Survey OOB' => new ValueMapper('LineItemID__r.Product__r.Name', new SurveyMapper()),
		'Preemptible' => new ValueMapper('LineItemID__r.Product__r.Default_Booking_Type__c', new IsPreEmptibleMapper()),
		'House' => new ValueMapper('LineItemID__r.Line_Name__c', new IsHouseMApper()),
		'Cancelled' => new ValueMapper('LineItemID__r.CancelledSystems__c', new CancelledMapper()),
		'Added Value' => new ValueMapper('LineItemID__r.Added_Value_Boolean__c', new IsAVMapper()),
		'Clean Slate' => new ValueMapper('LineItemID__r.CleanSlate__c', new CleantSlateMapper()),
		'No Charge Reason Code' => new ValueMapper('LineItemID__r.NoChargeReason__c', new NoChReasonMapper()),
		'Line Item Revenue Recognition Type' => new ValueMapper('', new HardCodeMapper('Invoiced')),
		'Line Item Section ID' => new ValueMapper('LineItemID__r.ProposalProductGroup__r.LineItemSectionID__c', new GroupSectionIdMapper()),
		'Line Item Section Name' => new ValueMapper('LineItemID__r.ProposalProductGroup__r.Name', new GroupNameMapper()),
		'Line Item Sort Order' => new ValueMapper('LineItemID__r.OrderNumber__c', new LIOrderMapper()),
		'Makegood' => new ValueMapper('LineItemID__r.MakeGood__c', new MakeGoodMapper()),
		'Net Line Item Cost' => new ValueMapper('LineContractTotalNet__c', new LINetCostMapper()),
		'Net Order Cost' => new ValueMapper('OrderBilling__r.Proposal__r.NetValue__c', new OrderNetCostMapper()),
		'Network Based Currency' => new ValueMapper('LineItemID__r.CurrencyIsoCode', new LICurrencyMapper()),
		'Order Action Quantity' => new ValueMapper('LineItemID__r.DFPActions__c', new OrderActionQuantity()),
		'Order Click Quantity' => new ValueMapper('OrderBilling__r.Proposal__r.ClicksSum__c', new TotalClicksMapper()),
		'Order Cost without discounts' => new ValueMapper('OrderBilling__r.Proposal__r.Total_Budget__c', new TotalGrossCostMapper()),
		'Order Currency' => new ValueMapper('OrderBilling__r.Proposal__r.OrderCurrency__c', new OrderCurrencyMapper()),
		'Measurement Study Funding Source' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.MeasurementStudyFundingSource__c', new MeasurStudyFndgMapper()),
		'Vertical' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.Vertical__c', new VerticalMapper()),
		'Secondary Benchmark' => new ValueMapper(''), // TODO: ask field
		'Primary Benchmark' => new ValueMapper(''), // TODO: ask field
		'Secondary KPI' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__r.Secondary_Validation_Goal_KPI__c', new SecKPIMapper()),
		'Primary KPI' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__r.Primary_Measurement_Goal_KPI__c', new PrKPIMapper()),
		'Automated Guaranteed' => new ValueMapper('OrderBilling__r.Proposal__r.ProgrammaticGuaranteed__c', new PGMapper()),
		'In-View Details' => new ValueMapper(new String[]{
			'OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.AMAC_Viewability_1__c',
			'OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.AMAC_Viewability_6__c',
			'OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.AMAC_Viewability_9__c'
		}, new InViewDtlsMapper()),
		'In-View Billing' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.AMAC_Viewability_1__c', new InViewBlngMapper()),
		'Billing Analyst Notes' => new ValueMapper('OrderBilling__r.Proposal__r.AnalystNotes__c', new AnalystNtsMapper()),
		'Billable Source Vendor Name' => new ValueMapper('BillingSource__c'),
		'Billing Notes' => new ValueMapper('OrderBilling__r.Proposal__r.BillingNotes__c', new BillingNotesMapper()),
		'Billing Password' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.BillingPassword__c', new BillingPswdMapper()),
		'Billing Username' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.BillingUsername__c', new BillingUsnmMapper()),
		'Cancellation does not comply with terms' => new ValueMapper(''), // TODO: empty info
		'Industry Segment' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.Vertical__c', new VerticalMapper()),
		'# of invoices' => new ValueMapper('', new HardCodeMapper('Single Invoice')),
		'Restricted Agency/Advertiser' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__r.Account.Agency_Caution_List__c', new RestrAgAdvMapper()),
		'Do Not Bill' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.DoNotBill__c', new DoNotBillMapper()),
		'Payment Type' => new ValueMapper('OrderBilling__r.Proposal__r.Payment_Type__c', new PaymentTypeMapper()),
		'Paying Fees' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.PayingFees__c', new PayingFeesMapper()),
		'Order Size' => new ValueMapper('OrderBilling__r.Proposal__c', new MinOrdMapper()),
		'Solbright IO Number' => new ValueMapper('', new HardCodeMapper('0')),
		'Solbright Contract ID' => new ValueMapper('', new HardCodeMapper('0')),
		'Effective Cancellation Date' => new ValueMapper('OrderBilling__r.Proposal__r.EffectiveCancellationDate__c', new EfCancDateMapper()),
		'Client Segmentation' => new ValueMapper(''), // TODO: empty info
		'Cancellation Details' => new ValueMapper('OrderBilling__r.Proposal__r.CancellationDetails__c', new CancelDtlsMapper()),
		'Order End Date' => new ValueMapper('OrderBilling__r.Proposal__r.End_Date__c', new OrderEDMapper()),
		'Order Impression Quantity' => new ValueMapper('OrderBilling__r.Proposal__r.Total_Impressions__c', new OrderImprMapper()),
		'Order Owner' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__c', new CampaignManagersMapper()),
		'Order Placement Quantity' => new ValueMapper('', new HardCodeMapper('0')),
		'Order Primary Team' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__c', new OrderPrimaryTeamMapper()),
		'Order Sales Stage' => new ValueMapper('OrderBilling__r.Proposal__r.Stage__c', new OrderStageMapper()),
		'Order Start Date' => new ValueMapper('OrderBilling__r.Proposal__r.Start_Date__c', new OrderSDMapper()),
		'Parent Line Item ID' => new ValueMapper('', new HardCodeMapper('')),
		'Percent Discrepancy' => new ValueMapper(new String[]{'FirstPartyUnits__c', 'ThirdPartyUnits__c'}, new PercDiscrepMapp()),
		'Primary Production System' => new ValueMapper('', new HardCodeMapper('Weather - DFP Premium')),
		'Product ID' => new ValueMapper('LineItemID__r.Product__r.ProductID__c', new LINameIdMapper()),
		'Commission Setting' => new ValueMapper(''),
		'Product Name' => new ValueMapper('LineItemID__r.Product__r.Name', new OPNameMapper()),
		'Ratecard' => new ValueMapper('', new HardCodeMapper('Ratecard')),
		'Recognized Revenue' => new ValueMapper(new String[]{'CalculatedUnits__c', 'BillingRate__c', 'LineItemID__r.ContractUnitPrice__c', 'AgencyDiscount__c'}, new RecogRevMapper()),
		'Remaining Amount' => new ValueMapper('RemainingAmount__c'),
		'Remaining Units' => new ValueMapper('RemainingUnits__c'),
		'Third Party Production System' => new ValueMapper('BillingSource__c', new ThrdPrtProdSysMapper()),
		'Total Line Item Discount Percentage' => new ValueMapper('AgencyDiscount__c', new AgencyDscMapper()),
		'Cumulative Recognized Revenue' => new ValueMapper('Id'),
		'Invoice Schedule - Cumulative Suggested Invoice Amount' => new ValueMapper('', new HardCodeMapper('0')),
		'Invoice Schedule - Cumulative Suggested Invoice Units' => new ValueMapper('', new HardCodeMapper('0')),
		'Order Alternate ID' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.AMAC_General_3__c', new OrdAltIdMapper()),
		'Product Tags' => new ValueMapper(''),
		'Invoice Assigned To' => new ValueMapper(''),
		'Primary Advertiser' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__r.Account.Name', new PrimAdvertiserMapper()),
		'Second Advertiser' => new ValueMapper(''),
		'Buying Agency' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__r.Buying_Agency__r.Name', new BAgencyMapper()),
		'Creative Agency' => new ValueMapper(''),
		'Other Partner' => new ValueMapper(''),
		'Rich Media Partner' => new ValueMapper(''),
		'Broker' => new ValueMapper(''),
		'Third Party' => new ValueMapper('BillingSource__c', new ThrdPrtProdSysMapper()),
		'Planning Agency' => new ValueMapper(''),
		'Billing Partner' => new ValueMapper('', new HardCodeMapper('')),
		'VAT Registration Number' => new ValueMapper('', new HardCodeMapper('')),
		'General Notes' => new ValueMapper('LineItemID__r.Notes__c', new LINotesMapper()),
		'Inside Sales' => new ValueMapper('', new HardCodeMapper('false')),
		'Credit Check Amount' => new ValueMapper('', new HardCodeMapper('0')),
		'Credit Check' => new ValueMapper('', new HardCodeMapper('true')),
		'Accounting Notes' => new ValueMapper('OrderBilling__r.Proposal__r.AnalystNotes__c', new AnalystNtsMapper()),
		'Global' => new ValueMapper('LineItemID__r.CurrencyIsoCode', new GlobalMapper()),
		'Additional Salesperson' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__c', new AddlPersonMapper()),
		'Planner' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__c', new PlannerMapper()),
		'Ad Ops Consultant' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__c', new CampaignManagersMapper()),
		'Watcher' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__c', new WatcherMapper()),
		'Creative Service Rep' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__c', new CrtSrvRepMapper()),
		'Finance Mgr' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__c', new FinMgrMapper()),
		'Primary Trafficker' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__c', new PrimTraffikerMapper()),
		'Sold To Billing Id' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.BillingAccount__r.IBM_Billing_ID__c', new SoldToCMRMapper()),
		'Sold To NetSuite Id' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.BillingAccount__r.Phy_NS_Address_ID__c', new SoldToMPPMapper()),
		'Bill To Billing Id' => new ValueMapper(new List<String>{'OrderBilling__r.Proposal__r.Opportunity__r.SoldToAccount__r.IBM_Billing_ID__c', 'OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.BillingAccount__r.IBM_Billing_ID__c'}, new BillToCMRMapper()),
		'Bill To NetSuite Id' => new ValueMapper(new List<String>{'OrderBilling__r.Proposal__r.Opportunity__r.SoldToAccount__r.Mail_NS_Address_ID__c', 'OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.BillingAccount__r.Mail_NS_Address_ID__c'}, new BillToMPPMapper()),
		'Ship To Billing Id' => new ValueMapper(new List<String>{'OrderBilling__r.Proposal__r.Opportunity__r.Account.IBM_Billing_ID__c', 'OrderBilling__r.Proposal__r.Opportunity__r.Account.IBM_Billing_ID__c'}, new ShipToCMRMapper()),
		'Ship To NetSuite Id' => new ValueMapper(new List<String>{'OrderBilling__r.Proposal__r.Opportunity__r.Account.Phy_NS_Address_ID__c', 'OrderBilling__r.Proposal__r.Opportunity__r.Account.Phy_NS_Address_ID__c'}, new ShipToMPPMapper()),
		'Email MPOC' => new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__r.SendInvoiceToMainContact__c', new EmailMPOCMapper())
	};

	static {
		EXPORT_COLUMNS_MAPPING_FE = EXPORT_COLUMNS_MAPPING.clone();
		EXPORT_COLUMNS_MAPPING_FE.put('Line Item Start Date', new ValueMapper('LineStartDate__c', new LIStartDateMapperFE()));
		EXPORT_COLUMNS_MAPPING_FE.put('Line Item End Date', new ValueMapper('LineEndDate__c', new LIEndDateMapperFE()));
		EXPORT_COLUMNS_MAPPING_FE.put('Billing Period Name', new ValueMapper('BillingPeriod__r.Billing_Start_Date__c', new PeriodNameMapperFE()));
		EXPORT_COLUMNS_MAPPING_FE.put('Billing Period Id', new ValueMapper('BillingPeriod__c', new PeriodIdMapperFE()));
		EXPORT_COLUMNS_MAPPING_FE.put('Order ID', new ValueMapper('LineItemID__r.Proposal__r.Operative_Order_Id__c', new OrderIdMapperFE()));
		EXPORT_COLUMNS_MAPPING_FE.put('Invoice ID', new ValueMapper('OrderBilling__r.Operative_Invoice_ID__c', new InvoiceIdMapperFE()));
		EXPORT_COLUMNS_MAPPING_FE.put('Line Item ID', new ValueMapper('LineItemID__r.Operative_Order_LineID__c', new LIIdMapperFE()));
		EXPORT_COLUMNS_MAPPING_FE.put('Billing Account ID', new ValueMapper('OrderBilling__r.Proposal__r.BillingAccount__r.Operative_Account_Id__c', new AccountIdMapperFE()));
		EXPORT_COLUMNS_MAPPING_FE.put('Billing Contact ID', new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__c', new BCIdMapperFE()));
		EXPORT_COLUMNS_MAPPING_FE.put('Invoice Schedule - Suggested Invoice Amount', new ValueMapper('', new HardCodeMapper(0)));
		EXPORT_COLUMNS_MAPPING_FE.put('Invoice Schedule - Suggested Invoice Units', new ValueMapper('', new HardCodeMapper(0)));
		EXPORT_COLUMNS_MAPPING_FE.put('Opportunity Cost Amount', new ValueMapper('', new HardCodeMapper(null))); //@TODO ????
		EXPORT_COLUMNS_MAPPING_FE.put('Platform Percentages', new ValueMapper('', new HardCodeMapper(0)));
		EXPORT_COLUMNS_MAPPING_FE.put('Network', new ValueMapper('LineItemID__r.Proposal__r.Network__c', new IsNetworkMapperFE()));
		EXPORT_COLUMNS_MAPPING_FE.put('National Preempt', new ValueMapper('LineItemID__r.Product__r.Default_Booking_Type__c', new IsPreEmptibleMapperFE()));
		EXPORT_COLUMNS_MAPPING_FE.put('Video', new ValueMapper('LineItemID__r.Product__r.Filter_1__c', new IsVideoMapperFE()));
		EXPORT_COLUMNS_MAPPING_FE.put('Weather Triggering', new ValueMapper('LineItemID__c', new IsWeatherTriggeringMapperFE()));
		EXPORT_COLUMNS_MAPPING_FE.put('Survey OOB', new ValueMapper('LineItemID__r.Product__r.Name', new SurveyMapperFE()));
		EXPORT_COLUMNS_MAPPING_FE.put('Preemptible', new ValueMapper('LineItemID__r.Product__r.Default_Booking_Type__c', new IsPreEmptibleMapperFE()));
		EXPORT_COLUMNS_MAPPING_FE.put('House', new ValueMapper('LineItemID__r.Line_Name__c', new IsHouseMApperFE()));
		EXPORT_COLUMNS_MAPPING_FE.put('Cancelled', new ValueMapper('LineItemID__r.CancelledSystems__c', new CancelledMapperFE()));
		EXPORT_COLUMNS_MAPPING_FE.put('Added Value', new ValueMapper('LineItemID__r.Added_Value_Boolean__c', new IsAVMapperFE()));
		EXPORT_COLUMNS_MAPPING_FE.put('Clean Slate', new ValueMapper('LineItemID__r.CleanSlate__c', new CleantSlateMapperFE()));
		EXPORT_COLUMNS_MAPPING_FE.put('Line Item Section ID', new ValueMapper('LineItemID__r.ProposalProductGroup__r.LineItemSectionID__c', new GroupSectionIdMapperFE()));
		EXPORT_COLUMNS_MAPPING_FE.put('Restricted Agency/Advertiser', new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__r.Account.Agency_Caution_List__c', new RestrAgAdvMapperFE()));
		EXPORT_COLUMNS_MAPPING_FE.put('Do Not Bill', new ValueMapper('OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.DoNotBill__c', new DoNotBillMapperFE()));
		EXPORT_COLUMNS_MAPPING_FE.put('Inside Sales', new ValueMapper('', new HardCodeMapper(false)));
		EXPORT_COLUMNS_MAPPING_FE.put('Solbright IO Number', new ValueMapper('', new HardCodeMapper(0)));
		EXPORT_COLUMNS_MAPPING_FE.put('Solbright Contract ID', new ValueMapper('', new HardCodeMapper(0)));
		EXPORT_COLUMNS_MAPPING_FE.put('Order Placement Quantity', new ValueMapper('', new HardCodeMapper(0)));
		EXPORT_COLUMNS_MAPPING_FE.put('Parent Line Item ID', new ValueMapper('', new HardCodeMapper(null)));
		EXPORT_COLUMNS_MAPPING_FE.put('Product ID', new ValueMapper('LineItemID__r.Product__r.ProductID__c', new LINameIdMapperFE()));
		EXPORT_COLUMNS_MAPPING_FE.put('Invoice Schedule - Cumulative Suggested Invoice Amount', new ValueMapper('', new HardCodeMapper(0)));
		EXPORT_COLUMNS_MAPPING_FE.put('Invoice Schedule - Cumulative Suggested Invoice Units', new ValueMapper('', new HardCodeMapper(0)));
		EXPORT_COLUMNS_MAPPING_FE.put('VAT Registration Number', new ValueMapper('', new HardCodeMapper(null)));
		EXPORT_COLUMNS_MAPPING_FE.put('Credit Check Amount', new ValueMapper('', new HardCodeMapper(0)));
		EXPORT_COLUMNS_MAPPING_FE.put('Credit Check', new ValueMapper('', new HardCodeMapper(true)));
		EXPORT_COLUMNS_MAPPING_FE.put('Line Invoice ID', new ValueMapper('Operative_ID_Formula__c', new LineInvoiceIdMapperFE()));
	}

	public static final Map<String, String> EXPORT_COLUMNS_TO_FIN_EXP = new Map<String, String>{
		'# of invoices' => 'Number_of_Invoices__c',
		'Accounting Notes' => 'Accounting_Notes__c',
		'Actual Invoice Units Term Source' => 'Actual_Invoice_Units_Term_Source__c',
		'Actual Invoice Units Term Used' => 'Actual_Invoice_Units_Term_Used__c',
		'Actual Net Invoice Amount Term Source' => 'Actual_Net_Invoice_Amount_Term_Source__c',
		'Actual Net Invoice Amount Term Used' => 'Actual_Net_Invoice_Amount_Term_Used__c',
		'Actual Revenue Recognition Term Source' => 'Actual_Revenue_Recognition_Term_Source__c',
		'Actual Revenue Recognition Term Used' => 'Actual_Revenue_Recognition_Term_Used__c',
		'Ad Ops Consultant' => 'Ad_Ops_Consultant__c',
		'Ad Type' => 'Ad_Type__c',
		'Added Value' => 'Added_Value__c',
		'Added Value Amount' => 'Added_Value_Amount__c',
		'Additional Salesperson' => 'Additional_Salesperson__c',
		'Additional Third Party Billing Source' => 'Additional_Third_Party_Billing_Source__c',
		'Advertiser Placement Name' => 'Advertiser_Placement_Name__c',
		'Agency Discount Percentage' => 'Agency_Discount_Percentage__c',
		'Automated Guaranteed' => 'Automated_Guaranteed__c',
		'Billable Source Vendor Name' => 'Billable_Source_Vendor_Name__c',
		'Billing Account Address 1' => 'Billing_Account_Address_1__c',
		'Billing Account Address 2' => 'Billing_Account_Address_2__c',
		'Billing Account - Billing ID' => 'Billing_Account_Billing_ID__c',
		'Billing Account City' => 'Billing_Account_City__c',
		'Billing Account Country' => 'Billing_Account_Country__c',
		'Billing Account Credit Status' => 'Billing_Account_Credit_Status__c',
		'Billing Account Email' => 'Billing_Account_Email__c',
		'Billing Account ID' => 'Billing_Account_ID__c',
		'Billing Account Name' => 'Billing_Account_Name__c',
		'Billing Account Phone' => 'Billing_Account_Phone__c',
		'Billing Account State/Province/Region' => 'Billing_Account_State_Province_Region__c',
		'Billing Account Zip/Postal_Code' => 'Billing_Account_Zip_Postal_Code__c',
		'Billing Analyst Notes' => 'Billing_Analyst_Notes__c',
		'Billing Contact' => 'Billing_Contact__c',
		'Billing Contact Address 1' => 'Billing_Contact_Address_1__c',
		'Billing Contact Address 2' => 'Billing_Contact_Address_2__c',
		'Billing Contact City' => 'Billing_Contact_City__c',
		'Billing Contact Country' => 'Billing_Contact_Country__c',
		'Billing Contact Email' => 'Billing_Contact_Email__c',
		'Billing Contact Fax' => 'Billing_Contact_Fax__c',
		'Billing Contact ID' => 'Billing_Contact_ID__c',
		'Billing Contact Phone' => 'Billing_Contact_Phone__c',
		'Billing Contact State/Province/Region' => 'Billing_Contact_State_Province_Region__c',
		'Billing Contact Zip' => 'Billing_Contact_Zip__c',
		'Billing Notes' => 'Billing_Notes__c',
		'Billing Partner' => 'Billing_Partner__c',
		'Billing Password' => 'Billing_Password__c',
		'Billing Period End Date' => 'Billing_Period_End_Date__c',
		'Billing Period Name' => 'Billing_Period_Name__c',
		'Billing Period Id' => 'BillingPeriodId__c',
		'Billing Period Scheme Name' => 'Billing_Period_Scheme_Name__c',
		'Billing Period Start Date' => 'Billing_Period_Start_Date__c',
		'Billing Terms ID' => 'Billing_Terms_ID__c',
		'Billing Terms Name' => 'Billing_Terms_Name__c',
		'Billing Username' => 'Billing_Username__c',
		'Broker' => 'Broker__c',
		'Buying Agency' => 'Buying_Agency__c',
		'Cancel Reason Code' => 'Cancel_Reason_Code__c',
		'Cancellation Amount' => 'Cancellation_Amount__c',
		'Cancellation Details' => 'Cancellation_Details__c',
		'Cancellation does not comply with terms' => 'Cancellation_does_not_comply_with_terms__c',
		'Cancelled' => 'Cancelled__c',
		'Clean Slate' => 'Clean_Slate__c',
		'Clean Slate Amount' => 'Clean_Slate_Amount__c',
		'Client Segmentation' => 'Client_Segmentation__c',
		'Commission Setting' => 'Commission_Setting__c',
		'Comp Opportunity' => 'Comp_Opportunity__c',
		'Creative Agency' => 'Creative_Agency__c',
		'Creative Service Rep' => 'Creative_Service_Rep__c',
		'Creative Type' => 'Creative_Type__c',
		'Credit Check' => 'Credit_Check__c',
		'Credit Check Amount' => 'Credit_Check_Amount__c',
		'Cumulative Discrepancy' => 'Cumulative_Discrepancy__c',
		'Cumulative Invoice Units' => 'Cumulative_Invoice_Units__c',
		'Cumulative Net Invoice Amount' => 'Cumulative_Net_Invoice_Amount__c',
		'Cumulative Percent Discrepancy' => 'Cumulative_Percent_Discrepancy__c',
		'Cumulative Primary Performance' => 'Cumulative_Primary_Performance__c',
		'Cumulative Recognized Revenue' => 'Cumulative_Recognized_Revenue__c',
		'Cumulative Third Party Performance' => 'Cumulative_Third_Party_Performance__c',
		'Discrepancy Amount' => 'Discrepancy_Amount__c',
		'Do Not Bill' => 'Do_Not_Bill__c',
		'Effective Cancellation Date' => 'Effective_Cancellation_Date__c',
		'External PO number' => 'External_PO_number__c',
		'Finance Mgr' => 'Finance_Mgr__c',
		'General Notes' => 'General_Notes__c',
		'Global' => 'Global__c',
		'Gross Invoice Amount' => 'Gross_Invoice_Amount__c',
		'Gross Line Item Cost' => 'Gross_Line_Item_Cost__c',
		'Gross Line Item Unit Cost' => 'Gross_Line_Item_Unit_Cost__c',
		'Gross Order Cost' => 'Gross_Order_Cost__c',
		'House' => 'House__c',
		'In-View Billing' => 'In_View_Billing__c',
		'In-View Details' => 'In_View_Details__c',
		'Industry Segment' => 'Industry_Segment__c',
		'Inside Sales' => 'Inside_Sales__c',
		'Invoice Amount without discounts' => 'Invoice_Amount_without_discounts__c',
		'Invoice Assigned To' => 'Invoice_Assigned_To__c',
		'Invoice ID' => 'Invoice_ID__c',
		'Invoice Name' => 'Invoice_Name__c',
		'Invoice Review Status' => 'Invoice_Review_Status__c',
		'Invoice Units' => 'Invoice_Units__c',
		'Invoice Version' => 'Invoice_Version__c',
		'Invoice Schedule - Cumulative Suggested Invoice Amount' => 'InvoiceSchdule_CumulatveSuggestdInvceAmt__c',
		'Invoice Schedule - Cumulative Suggested Invoice Units' => 'InvoiceSchdule_CumulativeSugstdInvceUnts__c',
		'Invoice Schedule - Suggested Invoice Amount Terms' => 'InvoiceSchedule_SuggestedInvceAmntTerms__c',
		'Invoice Schedule - Suggested Invoice Amount' => 'InvoiceSchedule_SuggestedInvceAmnt__c',
		'Invoice Schedule - Suggested Invoice Unit Terms' => 'Invoice_Schedule_SuggestedInvceUnitTerms__c',
		'Invoice Schedule - Suggested Invoice Units' => 'Invoice_Schedule_SuggestedInvceUnits__c',
		'Invoicing Organization Name' => 'Invoicing_Organization_Name__c',
		'Invoicing Organization Type' => 'Invoicing_Organization_Type__c',
		'Last Billing Period' => 'Last_Billing_Period__c',
		'Line Invoice ID' => 'LineInvoiceId__c',
		'Line Item Booking Type' => 'Line_Item_Booking_Type__c',
		'Line Item Cost Method' => 'Line_Item_Cost_Method__c',
		'Line Item End Date' => 'Line_Item_End_Date__c',
		'Line Item ID' => 'Line_Item_ID__c',
		'Line Item Name' => 'Line_Item_Name__c',
		'Line Item Notes' => 'Line_Item_Notes__c',
		'Line Item Quantity' => 'Line_Item_Quantity__c',
		'Line Item Revenue Recognition Type' => 'Line_Item_Revenue_Recognition_Type__c',
		'Line Item Section ID' => 'Line_Item_Section_ID__c',
		'Line Item Section Name' => 'Line_Item_Section_Name__c',
		'Line Item Sort Order' => 'Line_Item_Sort_Order__c',
		'Line Item Start Date' => 'Line_Item_Start_Date__c',
		'Line Item Unit Cost Before Discounts' => 'Line_Item_Unit_Cost_Before_Discounts__c',
		'Makegood' => 'Makegood__c',
		'Makegood Amount' => 'Makegood_Amount__c',
		'Measurement Study Funding Source' => 'Measurement_Study_Funding_Source__c',
		'National Preempt' => 'National_Preempt__c',
		'Net Invoice Amount' => 'Net_Invoice_Amount__c',
		'Net Line Item Cost' => 'Net_Line_Item_Cost__c',
		'Net Line Item Unit Cost' => 'Net_Line_Item_Unit_Cost__c',
		'Net Order Cost' => 'Net_Order_Cost__c',
		'Network' => 'Network__c',
		'Network Based Currency' => 'Network_Based_Currency__c',
		'No Charge Reason Code' => 'No_Charge_Reason_Code__c',
		'Opportunity Cost Amount' => 'Opportunity_Cost_Amount__c',
		'Order Action Quantity' => 'Order_Action_Quantity__c',
		'Order Alternate ID' => 'Order_Alternate_ID__c',
		'Order Click Quantity' => 'Order_Click_Quantity__c',
		'Order Cost without discounts' => 'Order_Cost_without_discounts__c',
		'Order Currency' => 'Order_Currency__c',
		'Order End Date' => 'Order_End_Date__c',
		'Order ID' => 'Order_ID__c',
		'Order Impression Quantity' => 'Order_Impression_Quantity__c',
		'Order Name' => 'Order_Name__c',
		'Order Owner' => 'Order_Owner__c',
		'Order Placement Quantity' => 'Order_Placement_Quantity__c',
		'Order Primary Team' => 'Order_Primary_Team__c',
		'Order Sales Stage' => 'Order_Sales_Stage__c',
		'Order Size' => 'Order_Size__c',
		'Order Start Date' => 'Order_Start_Date__c',
		'Other Partner' => 'Other_Partner__c',
		'Parent Line Item ID' => 'Parent_Line_Item_ID__c',
		'Paying Fees' => 'Paying_Fees__c',
		'Payment Type' => 'Payment_Type__c',
		'Percent Discrepancy' => 'Percent_Discrepancy__c',
		'Planner' => 'Planner__c',
		'Planning Agency' => 'Planning_Agency__c',
		'Platform Percentages' => 'Platform_Percentages__c',
		'Preemptible' => 'Preemptible__c',
		'Primary Advertiser' => 'Primary_Advertiser__c',
		'Primary Benchmark' => 'Primary_Benchmark__c',
		'Primary KPI' => 'Primary_KPI__c',
		'Primary Performance' => 'Primary_Performance__c',
		'Primary Production System' => 'Primary_Production_System__c',
		'Primary Salesperson' => 'Primary_Salesperson__c',
		'Primary Trafficker' => 'Primary_Trafficker__c',
		'Product ID' => 'Product_ID__c',
		'Product Name' => 'Product_Name__c',
		'Product Tags' => 'Product_Tags__c',
		'Ratecard' => 'Ratecard__c',
		'Recognized Revenue' => 'Recognized_Revenue__c',
		'Remaining Amount' => 'Remaining_Amount__c',
		'Remaining Units' => 'Remaining_Units__c',
		'Reporting Notes' => 'Reporting_Notes__c',
		'Restricted Agency/Advertiser' => 'Restricted_Agency_Advertiser__c',
		'Revenue Ad Type' => 'Revenue_Ad_Type__c',
		'Rich Media Partner' => 'Rich_Media_Partner__c',
		'Second Advertiser' => 'Second_Advertiser__c',
		'Secondary Benchmark' => 'Secondary_Benchmark__c',
		'Secondary KPI' => 'Secondary_KPI__c',
		'Solbright Campaign ID' => 'Solbright_Campaign_ID__c',
		'Solbright Contract ID' => 'Solbright_Contract_ID__c',
		'Solbright IO Number' => 'Solbright_IO_Number__c',
		'Solbright LI ID' => 'Solbright_LI_ID__c',
		'Survey OOB' => 'Survey_OOB__c',
		'Third Party' => 'Third_Party__c',
		'Third Party Performance' => 'Third_Party_Performance__c',
		'Third Party Production System' => 'Third_Party_Production_System__c',
		'Total Line Item Discount Percentage' => 'Total_Line_Item_Discount_Percentage__c',
		'Unit Type' => 'Unit_Type__c',
		'Unrecognized Revenue' => 'Unrecognized_Revenue__c',
		'VAT Registration Number' => 'VAT_Registration_Number__c',
		'Vertical' => 'Vertical__c',
		'Video' => 'Video__c',
		'Watcher' => 'Watcher__c',
		'Weather Triggering' => 'Weather_Triggering__c',
		'Sold To Billing Id' => 'Sold_To_CMR__c',
		'Sold To NetSuite Id' => 'Sold_To_MPP__c',
		'Bill To Billing Id' => 'Bill_To_CMR__c',
		'Bill To NetSuite Id' => 'Bill_To_MPP__c',
		'Ship To Billing Id' => 'Ship_To_CMR__c',
		'Ship To NetSuite Id' => 'Ship_To_MPP__c',
		'Email MPOC' => 'Email_MPOC__c'
	};

	private static PFX_BillingReportService instance;
	public static PFX_BillingReportService getService() {
		if (instance == null) {
			instance = new PFX_BillingReportService();
		}
		return instance;
	}

	webService static String receiveData(String periodId, Integer page, String billingStatus, String searchTerm, Boolean isFinal) {
		return receiveDataByTimeAndBillingStatusAndSearchTerm(periodId, page, null, billingStatus, searchTerm, isFinal, null);
	}

	webService static String receiveDataByTimeAndBillingStatusAndSearchTerm(String periodId, Integer page, Long to, String billingStatus, String searchTerm, Boolean isFinal, String invoiceIds) {
		PFX_BillingDashboardDAO billingDAO = PFX_BillingDashboardDAO.getDao();
		List<PFXLineItemBilling__c> allInvoiceLineItems = new List<PFXLineItemBilling__c>();
		List<PFXLineItemBilling__c> invoiceLineItems = new List<PFXLineItemBilling__c>();
		PFX_BillingReportResponse result = new PFX_BillingReportResponse();
		
		if(page == null) {
			page = 0;
		}

		Integer nextPageStartIndex = ((page ?? 0) + 1) * PAGE_SIZE;
		Boolean searchByAccountExec = false;
		Datetime toTime = to != null ? Datetime.newInstance(to) : null;// toTime is used in SOQL via :toTime
		String[] filteredProposalIds = billingDAO.getFilteredProposals();
		Integer filterProposalFromId = billingDAO.getFilterProposalFromId();
		Set<String> billingInvoicesIds = new Set<String>();
		Set<String> billingPeriodsIds = new Set<String>{periodId};

		String searchString;
		if(String.isNotBlank(searchTerm)){
			searchString = '%' + searchTerm + '%';
		} 

		List<String> periodIds = new List<String>();
		if(String.isNotBlank(periodId)){
			periodIds = periodId.split(',');
		}

		List<String> invoiceIdsArray;
		if(invoiceIds != null) {
			invoiceIdsArray = invoiceIds.split(',');
		}

		PFX_BillingDashboardSearchDTO searchDTO = new PFX_BillingDashboardSearchDTO();
		searchDTO.billingPeriodsIds = periodIds;
		searchDTO.status = billingStatus;
		searchDTO.searchString = searchString;
		searchDTO.toDate = toTime;
		searchDTO.invoiceIds = invoiceIdsArray;
		searchDTO.columns = new List<String>{
			'advertiser', 'invoice_ID', 'order_ID', 'orderName', 'operativeOrderId', 'billingStatus', 'agency'
		};
		
		List<PFX_Order_Billing__c> orderBillings = billingDAO.getBillingInvoices(searchDTO);

		Set<Id> orderIds = new Set<Id>();
		for(PFX_Order_Billing__c ob : orderBillings){
			orderIds.add(ob.Id);
			billingInvoicesIds.add(ob.Id);
		}
		allInvoiceLineItems = billingDAO.getLineItemBillingsByOrderBillingIds(orderIds);
		
		if(!allInvoiceLineItems.isEmpty()){
			searchByAccountExec = true;
		}
		
		if (allInvoiceLineItems.isEmpty()) {
			billingInvoicesIds = new Set<String>();
			searchByAccountExec = true;
			PFX_BillingDashboardService.AccountExecSearchHelper helper = new PFX_BillingDashboardService.AccountExecSearchHelper();
			PFX_Order_Billing__c[] billingInvoices = helper.getBillingInvoices(billingStatus, periodId.split(','), searchTerm);

			for (PFX_Order_Billing__c invoice : billingInvoices) {
				billingInvoicesIds.add(invoice.Id);
			}

			allInvoiceLineItems = Database.query(String.escapeSingleQuotes(buildSOQL(to != null, false, billingInvoicesIds)));
		}

		if (allInvoiceLineItems.isEmpty()) {
			return JSON.serialize(result, true);
		}

		Integer totalSize = allInvoiceLineItems.size();

		Set<Id> ids = new Set<Id>();
		for (Integer index = page * PAGE_SIZE; index < totalSize && index < nextPageStartIndex; index++) {
			ids.add(allInvoiceLineItems[index].Id);
		}
		
		if (searchByAccountExec) {
			invoiceLineItems = Database.query(String.escapeSingleQuotes(buildSOQL(false, true, billingInvoicesIds)));
		} else {
			invoiceLineItems = getService().getRecords(periodId, ids, billingStatus, searchTerm);
		}

        Set<Id> oppIds = new Set<Id>();
		Set<Id> ppIds = new Set<Id>();
		Set<Id> pIds = new Set<Id>();

		for (PFXLineItemBilling__c invoiceLineItem : invoiceLineItems) {
			oppIds.add(invoiceLineItem.OrderBilling__r.Proposal__r.Opportunity__c);
			ppIds.add(invoiceLineItem.LineItemID__c);
			pIds.add(invoiceLineItem.OrderBilling__r.Proposal__c);
		}
		getContactCache().fillCache(oppIds);
		getPeriodCache().fillCache(invoiceLineItems);
		getGeoLayerCache().fillCache(ppIds);
		getSplitsCache().fillCache(oppIds);
		getDealTeamCache().fillCache(oppIds);
		getPropApCache().fillCache(pIds);

		Boolean skipStatusCheck = true; //String.isBlank(billingStatus);

		OP1_Fin_Export__c[] finExpRows = new OP1_Fin_Export__c[]{};
		for (PFXLineItemBilling__c invoiceLineItem : invoiceLineItems) {
			if (skipStatusCheck) {
				Object[] values = new Object[]{};
				OP1_Fin_Export__c finExpRow = new OP1_Fin_Export__c();
				for (String column : EXPORT_COLUMNS) {
					ValueMapper mapper = EXPORT_COLUMNS_MAPPING.get(column);
					Object v = mapper.getValue(invoiceLineItem);
					values.add(escapeCsv(v));

					if (isFinal && EXPORT_COLUMNS_TO_FIN_EXP.containsKey(column) && !CUMULATIVE_COLUMNS.contains(column)) {
						ValueMapper mapperFE = EXPORT_COLUMNS_MAPPING_FE.get(column);
						Object vFE = mapperFE.getValue(invoiceLineItem);
						finExpRow.put(EXPORT_COLUMNS_TO_FIN_EXP.get(column), vFE);
					}
				}

				if (isFinal) {
					String column = 'Line Invoice ID';
					ValueMapper mapperFE = EXPORT_COLUMNS_MAPPING_FE.get(column);
					Object vFE = mapperFE.getValue(invoiceLineItem);
					finExpRow.put(EXPORT_COLUMNS_TO_FIN_EXP.get(column), vFE);

					column = 'Billing Period Id';
					mapperFE = EXPORT_COLUMNS_MAPPING_FE.get(column);
					vFE = mapperFE.getValue(invoiceLineItem);
					finExpRow.put(EXPORT_COLUMNS_TO_FIN_EXP.get(column), vFE);

					finExpRows.add(finExpRow);
				}
				result.addRow(values);
			}
		}
		result.isLast = nextPageStartIndex >= totalSize;
		if (isFinal) {
			insert finExpRows;
		}
		return JSON.serialize(result, true);
	}

	private static Object escapeCsv(Object raw) {
		if ((raw instanceof String) && String.isNotBlank((String)raw)) {
			return ((String)raw).replace('"',' ').replace(',', ' ');
		}
		return raw;
	}

	webservice static void cleanUpFinExportRows(String periodId, String billingStatus, String searchTerm) {
		String[] filteredProposalIds = PFX_BillingDashboardDAO.getDao().getFilteredProposals();
		Integer filterProposalFromId = PFX_BillingDashboardDAO.getDao().getFilterProposalFromId();

		String searchString = '%' + searchTerm + '%';

		String soql = buildLineInvoicesSOQL(periodId, billingStatus, searchTerm);
		Set<Decimal> orderInvoicesOperativeIds = new Set<Decimal>();

		List<String> periodIds = new List<String>();
		if(String.isNotBlank(periodId)){
			periodIds = periodId.split(',');
		}

		PFXLineItemBilling__c[] libs = Database.query(String.escapeSingleQuotes(soql));

		if (libs.size() > 0) {
			for (PFXLineItemBilling__c lib:libs) {
				orderInvoicesOperativeIds.add(lib.OrderBilling__r.Operative_ID_Formula__c);
			}
		} else {
			PFX_BillingDashboardService.AccountExecSearchHelper helper = new PFX_BillingDashboardService.AccountExecSearchHelper();
			PFX_Order_Billing__c[] billingInvoices = helper.getBillingInvoices(billingStatus, periodId.split(','), searchTerm);

			for (PFX_Order_Billing__c invoice : billingInvoices) {
				orderInvoicesOperativeIds.add(invoice.Operative_ID_Formula__c);
			}
		}
		if (orderInvoicesOperativeIds.size() > 0) {
			OP1_Fin_Export__c[] toDelete = [
				SELECT Id
				FROM OP1_Fin_Export__c
				WHERE Invoice_ID__c in :orderInvoicesOperativeIds
			];
			delete toDelete;
		}
	}

	webservice static void createFinExportRequests(String periodId, Boolean isIERP) {
		if (periodId == null) throw new Proposal_FX_Exception('Period is undefined. Can\'t create export requests.');

		if(isIERP == null) throw new Proposal_FX_Exception('isIERP parameter is undefined. Please provide a valid value to this parameter: true/false');

		PFX_BillingDashboardService.getService().createFinExportRequests(periodId.split(','), isIERP);
	}

	/**
 	 * Retrieves the report header for the billing report.
 	 *
 	 * @param periodId      The period ID to filter the report by. Usually sent in this format: a3K2K000002AJWDUA4,a3K2K000002AJWDUA5
 	 * @param billingStatus The billing status to filter the report by.
 	 * @param searchTerm    The search term to filter the report by.
 	 * @return A JSON serialized string representing the billing report header.
 	**/
	webservice static String getReportHeader(String periodId, String billingStatus, String searchTerm, String invoiceIds) {

		PFX_BillingReportHeader result = new PFX_BillingReportHeader();
		
		List<String> periodIds = new List<String>();
		if(String.isNotBlank(periodId)){
			periodIds = periodId.split(',');
		}

		String searchString;
		if(String.isNotBlank(searchTerm)){
			searchString = '%' + searchTerm + '%';
		} 
		
		List<String> invoiceIdsArray;
		if(invoiceIds != null) {
			invoiceIdsArray = invoiceIds.split(',');
		}

		PFX_BillingDashboardSearchDTO searchDTO = new PFX_BillingDashboardSearchDTO();
		searchDTO.billingPeriodsIds = periodIds;
		searchDTO.status = billingStatus;
		searchDTO.searchString = searchString;
		searchDTO.getCurrentPeriod = false;
		searchDTO.invoiceIds = invoiceIdsArray;
		searchDTO.columns = new List<String>{
			'advertiser', 'invoice_ID', 'order_ID', 'orderName', 'operativeOrderId', 'billingStatus', 'agency'
		};

		PFX_BillingDashboardDAO billingDAO = PFX_BillingDashboardDAO.getDao();
		List<PFX_Order_Billing__c> orderBillings = billingDAO.getBillingInvoices(searchDTO);

		Set<Id> orderIds = new Set<Id>();
		for(PFX_Order_Billing__c ob : orderBillings){
			orderIds.add(ob.Id);
		}

		List<PFXLineItemBilling__c> lineItemBillings = billingDAO.getLineItemBillingsByOrderBillingIds(orderIds);
		if(lineItemBillings == null){
			result.count = 0;
		} else {
			result.count = lineItemBillings.size();
		}
		
		String xlsType;
		for (String exportColumn : EXPORT_COLUMNS) {
			xlsType = XLS_TYPES_EXPORT_COLUMNS.containsKey(exportColumn) ? XLS_TYPES_EXPORT_COLUMNS.get(exportColumn) : DEFAULT_XLS_TYPE;
			PFX_BillingReportHeader.Field fieldDef = new PFX_BillingReportHeader.Field(exportColumn, xlsType);
			result.fields.add(fieldDef);
		}

		Integer[] cumIndexes = new Integer[]{};
		for (Integer index = 0; index < EXPORT_COLUMNS.size(); index++) {
			String columnName = EXPORT_COLUMNS[index];
			if (CUMULATIVE_FIELDS.contains(columnName)) {
				cumIndexes.add(index);
			}
		}
		result.cumulativeIndexes = cumIndexes;
		result.pageSize = PAGE_SIZE;
		return JSON.serialize(result, true);
	}

	webservice static String getCumulativeInfo(String[] recordIds, Boolean isFinal) {
		InvoiceLineItemCache invCache = getInvoiceLineItemCache();
		Set<Id> ids = new Set<Id>();
		for (String recordId : recordIds) {
			ids.add(recordId);
		}
		invCache.fillCache(ids);
		Map<String, Object> cumulativeInfos = invCache.getCumulutiveInfo();
		if (isFinal) {
			invCache.updateFinExportCumulativeInfo(cumulativeInfos);
		}
		return JSON.serialize(cumulativeInfos);
	}

	class OpProductInfoResponse {
		String environmentType {get;set;}
		String adExchangeEnvironment {get;set;}
		PFX_AdTechDFPTargeting targeting {get;set;}
		String name {get;set;}
	}

	public static String getOperativeProductInfo(String operativeProductId, String[] toIds) {
		OpProductInfoResponse result = new OpProductInfoResponse();
		Operative_Products__c product = getOPById(operativeProductId);
		result.name = product.Name;
		result.environmentType = PFX_AdTechDFPConverter.getEnvironmentTypeByProductName(product.Name);
		result.adExchangeEnvironment = PFX_AdTechDFPConverter.getAdExchangeEnv(result.environmentType);
		PFX_AdTechDFPTargeting targeting = new PFX_AdTechDFPTargeting();
		Target_Options__c[] targetOptions = new Target_Options__c[] {};
		Target_Options__c[] embeddedTOs = getTargetEmbdeddedTargetOptions(operativeProductId);
		Target_Options__c[] requestedTOs = Proposal_FX_TargetOptionDao.getDao().findTargetOptionsForForecast(toIds);

		targetOptions.addAll(embeddedTOs);
		targetOptions.addAll(requestedTOs);
		PFX_AdTechDFPConverter.convertTargeting(targeting, targetOptions, null, new Set<Id>(), true);
		result.targeting = targeting;
		return JSON.serializePretty(result, true);
	}

	public static Target_Options__c[] getTargetEmbdeddedTargetOptions(String opId) {
		Target_Options__c[] targetOptions = Proposal_FX_TargetOptionService.getService().getEmbeddedOptionsOfOperativeProducts(new Set<Id>{opId});
		return targetOptions;
	}

	public static Operative_Products__c getOPById(String opId) {
		Operative_Products__c[] ops = [
			SELECT Id, Name
			FROM Operative_Products__c
			WHERE Id = :opId
		];
		if (ops.size() == 0) {
			return null;
		}
		return ops[0];
	}

    private PFXLineItemBilling__c[] getRecords(String periodId, Set<Id> ids, String billingStatus, String searchTerm) {
        // ids are used in SOQL via :ids
		String[] filteredProposalIds = PFX_BillingDashboardDAO.getDao().getFilteredProposals();
		Integer filterProposalFromId = PFX_BillingDashboardDAO.getDao().getFilterProposalFromId();
		String searchString = '%'+ searchTerm + '%';
        String soql = buildSOQL(periodId, false, true, billingStatus, searchTerm);

		List<String> periodIds = new List<String>();
		if(String.isNotBlank(periodId)){
			periodIds = periodId.split(',');
		}

        return Database.query(soql);
    }

	private static final String INVOICE_OBJECT_NAME =  Schema.PFXLineItemBilling__c.SObjectType.getDescribe().getName();

	private static final Set<String> DEFAULT_FIELDS = new Set<String> {
			'Id', 'OrderBilling__c', 'LineItemID__c', 'LineItemID__r.Proposal__c', 'OrderBilling__r.Proposal__r.Opportunity__c',
			'GrossAmount__c', 'BillingPeriod__c'
	};

	private static String getDefaultOrderBillingCondition() {
		return ' LineItemID__c != NULL AND OrderBilling__r.Proposal__r.RecordType.DeveloperName = :NATIONAL_TYPE '
				+ ' AND OrderBilling__r.Proposal__r.Opportunity__r.Account.Name != :Z_CYCLE '
				+ ' AND OrderBilling__r.Proposal__r.Primary_Proposal__c = TRUE '
				+ ' AND (OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__c = null OR OrderBilling__r.Proposal__r.Opportunity__r.AMAC_Checklist__r.DoNotBill__c  = FALSE) '
				+ '  AND OrderBilling__r.Proposal__r.Operative_Order_Id__c != null '
					+ ' AND (OrderBilling__r.Proposal__c in :filteredProposalIds '
					+ ' OR OrderBilling__r.Proposal__r.Operative_ID_Formula__c > :filterProposalFromId) ';
	}

	private static String buildCountSOQL(String periodId, String billingStatus, String searchTerm) {
		String result = 'SELECT count()' + buildLineInvoicesSOQLPart(periodId, billingStatus, searchTerm);
		return result;
	}

	private static String buildLineInvoicesSOQL(String periodId, String billingStatus, String searchTerm) {
		String result = 'SELECT Id, OrderBilling__c, OrderBilling__r.Operative_ID_Formula__c ' + buildLineInvoicesSOQLPart(periodId, billingStatus, searchTerm);
		return result;
	}

	private static String buildLineInvoicesSOQLPart(String periodId, String billingStatus, String searchTerm) {
		String result = ' FROM ' + INVOICE_OBJECT_NAME
				+ ' WHERE ' + getDefaultOrderBillingCondition();
		if (String.isNotBlank(periodId)) {
			result += ' AND (OrderBilling__r.BillingPeriod__c in (:periodId) OR OrderBilling__r.BillingPeriod__c in :periodIds)';
		}
		result += ' AND Inactive__c = false ';
		if (String.isNotBlank(billingStatus)) {
			result += ' AND OrderBilling__r.BillingStatus__c = ';
			if (billingStatus == 'noStatus') {
				result += 'NULL ';
			} else {
				result += ':billingStatus ';
			}
		}
		if (String.isNotBlank(searchTerm)) {
			result += ' AND (OrderBilling__r.PrimaryAdvertiser__r.Name LIKE :searchString'
					+ ' OR OrderBilling__r.Operative_Invoice_ID__c LIKE :searchString'
					+ ' OR OrderBilling__r.Proposal__r.Proposal_ID__c LIKE :searchString'
					+ ' OR OrderBilling__r.Proposal__r.Name LIKE :searchString'
					+ ' OR OrderBilling__r.BillingStatus__c LIKE :searchString'
					+ ' OR OrderBilling__r.Proposal__r.Operative_Order_Id__c LIKE :searchString) ';
		}
		return result;
	}

	public static String buildCountSOQL(Set<String> billingInvoicesIds) {
		return 'SELECT count() FROM ' + INVOICE_OBJECT_NAME + ' WHERE OrderBilling__c IN :billingInvoicesIds AND LineItemID__c != NULL';
	}

	public static String buildSOQL(String periodId, Boolean timeCondition, Boolean allFields, String billingStatus, String searchTerm) {
		String fields;
		if (allFields) {
			fields = String.join((Iterable<String>)getAllApiFields(), ',');
		} else {
			fields = ' ID ';
		}
		String result = 'SELECT ' + fields
				+ ' FROM ' + INVOICE_OBJECT_NAME
				+ ' WHERE ' + getDefaultOrderBillingCondition();
		if (String.isNotBlank(periodId)) {
			result += ' AND (OrderBilling__r.BillingPeriod__c IN (:periodId) OR OrderBilling__r.BillingPeriod__c IN :periodIds)';
		}
		result += ' AND Inactive__c = false ';
		if (allFields) {
			result += ' AND Id in :ids ';
		}
		if (timeCondition) {
			result += ' AND CreatedDate <= :toTime ';
		}
		if (String.isNotBlank(billingStatus)) {
			result += ' AND OrderBilling__r.BillingStatus__c = ';
			if (billingStatus == 'noStatus') {
				result += 'NULL ';
			} else {
				result += ':billingStatus ';
			}
		}
		if (String.isNotBlank(searchTerm)) {
			result += ' AND (OrderBilling__r.PrimaryAdvertiser__r.Name LIKE :searchString'
					+ ' OR OrderBilling__r.Operative_Invoice_ID__c LIKE :searchString'
					+ ' OR OrderBilling__r.Proposal__r.Proposal_ID__c LIKE :searchString'
					+ ' OR OrderBilling__r.Proposal__r.Name LIKE :searchString'
					+ ' OR OrderBilling__r.BillingStatus__c LIKE :searchString'
					+ ' OR OrderBilling__r.Proposal__r.Operative_Order_Id__c LIKE :searchString) ';
		}
		result += ' ORDER BY LineItemID__r.Proposal__r.Proposal_ID__c, OrderBilling__c ';
		return result;
	}

	public static String buildSOQL(Boolean timeCondition, Boolean allFields, Set<String> billingInvoicesIds) {
		String fields;
		if (allFields) {
			fields = String.join((Iterable<String>)getAllApiFields(), ',');
		} else {
			fields = ' ID ';
		}
		String result = 'SELECT ' + fields
				+ ' FROM ' + INVOICE_OBJECT_NAME
				+ ' WHERE OrderBilling__c IN :billingInvoicesIds AND LineItemID__c != NULL';

		if (allFields) {
			result += ' AND Id in :ids ';
		}
		if (timeCondition) {
			result += ' AND CreatedDate <= :toTime ';
		}

		result += ' ORDER BY LineItemID__r.Proposal__r.Proposal_ID__c, OrderBilling__c ';
		return result;
	}

	private static Set<String> getAllApiFields() {
		Set<String> result = new Set<String>();
		for (String defaultField : DEFAULT_FIELDS) {
			result.add(defaultField.toLowerCase());
		}
		for (ValueMapper mapper : EXPORT_COLUMNS_MAPPING.values()) {
			for (String field : mapper.getFields()) {
				if (String.isNotBlank(field)) {
					result.add(field.toLowerCase());
				}
			}
		}
		return result;
	}
}