/**
 * Contains general functionality, helper functions
 * locale, ...
 */

/*
 * Cookies
 */
function createCookie(name,value,days) {
	if (days) {
		var date = new Date();
		date.setTime(date.getTime()+(days*24*60*60*1000));
		var expires = "; expires="+date.toGMTString();
	}
	else var expires = "";
	document.cookie = name+"="+value+expires+"; path=/";
}

function readCookie(name) {
	var nameEQ = name + "=";
	var ca = document.cookie.split(';');
	for(var i=0;i < ca.length;i++) {
		var c = ca[i];
		while (c.charAt(0)==' ') c = c.substring(1,c.length);
		if (c.indexOf(nameEQ) == 0) return c.substring(nameEQ.length,c.length);
	}
	return null;
}

function eraseCookie(name) {
	createCookie(name,"",-1);
}


/*
 * Common functions
 */

function OpenInNewTab(url )
{
  var win=window.open(url, '_blank');
  win.focus();
}
String.prototype.format = function () {
	  var args = arguments;
	  return this.replace(/\{\{|\}\}|\{(\d+)\}/g, function (m, n) {
	    if (m == "{{") { return "{"; }
	    if (m == "}}") { return "}"; }
	    return args[n];
	  });
	};
// Correct date formatting
Date.prototype.format = function(format) //author: meizz
	{
	  var o = {
	    "M+" : this.getMonth()+1, //month
	    "d+" : this.getDate(),    //day
	    "h+" : this.getHours(),   //hour
	    "m+" : this.getMinutes(), //minute
	    "s+" : this.getSeconds(), //second
	    "q+" : Math.floor((this.getMonth()+3)/3),  //quarter
	    "S" : this.getMilliseconds() //millisecond
	  };
	
	  if(/(y+)/.test(format)) format=format.replace(RegExp.$1,
	    (this.getFullYear()+"").substr(4 - RegExp.$1.length));
	  for(var k in o)if(new RegExp("("+ k +")").test(format))
	    format = format.replace(RegExp.$1,
	      RegExp.$1.length==1 ? o[k] :
	        ("00"+ o[k]).substr((""+ o[k]).length));
	  return format;
	};
	

function pad(number, length){
    var str = "" + number;
    while (str.length < length) {
        str = '0'+str;
    }
    return str;
}
// Insert URL parameter
function insertParam(key, value)
{
    key = encodeURI(key); value = encodeURI(value);
    var kvp = document.location.search.substr(1).split('&');
    var i=kvp.length; var x; while(i--) 
    {
        x = kvp[i].split('=');

        if (x[0]==key)
        {
            x[1] = value;
            kvp[i] = x.join('=');
            break;
        }
    }
    if(i<0) {kvp[kvp.length] = [key,value].join('=');}
    //this will reload the page, it's likely better to store this until finished
    document.location.search = kvp.join('&'); 
}

/*
 * GUID(not real guid, but good enough for this usage) Generation 
 */
function s4() {
  return Math.floor((1 + Math.random()) * 0x10000)
             .toString(16)
             .substring(1);
};

function guid() {
  return s4() + s4() + '-' + s4() + '-' + s4() + '-' + s4() + '-' + s4() + s4() + s4();
}
/*
 * For making id for element
 */
function makeId()
{
    var text = "";
    var possible = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";

    for( var i=0; i < 5; i++ )
        text += possible.charAt(Math.floor(Math.random() * possible.length));

    return text;
}

/*
 * Localization
 */
function localizeUI(){
	if( $.url().param("lang") ){
		Locale.setLanguage($.url().param("lang"));
		$("[data-localize]").localize("locale", { language: $.url().param("lang") });
	}else{
		$("[data-localize]").localize("locale", { language: "en" });
	}
}
var Locale = {
		// Default set
		dict: {
			"GoalShare": "GoalShare",
			"Slogan": "Share public goals → Find collaborators",
			"Nav_Issues": "Issues",
			"Nav_Goals": "Goals",
			"Nav_Maps": "Maps",
			"Nav_People": "People",
			"Nav_Chronology": "Chronology",


			"Goal": "Goal",
			"Subgoal": "Subgoal",
			"ParentGoal": "Parent goal",
			"Title": "Title",
			"Description": "Description",
			"Reference": "Reference",
			
			"Socia_Issue": "Socia:Issue",
			"Socia_Goal": "Socia:Goal",
			
			"StartDate": "Start date",
			"EndDate": "End date",
			"CreatedDate": "Created date",
			"DesiredDate": "Desired date",
			"CreatedBy": "Created by",
			"Keyword": "keyword",
			"Status": "Status",
			"Status_NotStarted":"Not started",
			"Status_Aborted": "Aborted",
			"Status_InProgress":"In progress",
			"Status_Completed": "Completed",
			"Status_Unknown": "Unknown",
			"ResultLimit": "Result limit",
			"Subgoals": "SubGoals",
			"Subgoals_HeaderText":"Subgoals of the current goal",
			"Name":"Name",
			"Calendar": "Calendar",
			
			"Act_CreateGoal": "Create new goal",
			"Act_Search": "Search",
			"Act_AddSubgoal": "Add subgoal",
			"Act_listSubgoals": "Subgoals",
			"Act_Register": "Register",
			"Act_SignUp": "Sign up",
			"Act_SignUpSignIn": "Sign in / Sign up",
			"Act_Apply": "Apply",
			"Act_Cancel": "Cancel",
			
			"Err_NoResults": "No results",
			"Err_Error": "Error",
			"Err_ConnectionLost": "The connection has been lost",
			
			"T_MultiSelect_None": "None",
			"T_MultiSelect_All": "All",
			"T_MultiSelect_SelectedText":"# Selected",
			"X_DateFormat": "yyyy-MM-dd",
			"X_DateFormatJQ": "yy-mm-dd",
			"X_FullDateFormat": "yyyy-MM-ddThh:mm:ss",
			
			"CompletedDate":"Completed date",
			"CompetedDate":"Completed date",
			"Act_GetInfo":"Details",
			"SubgoalsHeader": "Subgoals",
			"RequiredDate": "Required date",
			"Act_FindSimilarGoals": "Similar goals",
			"Act_FindCollaborators": "Collaborators",
			"Status_Icon_NotStarted":"img/png/32x32/comments.png",
			"Status_Icon_Aborted": "img/png/32x32/warning.png",
			"Status_Icon_InProgress":"img/png/32x32/process.png",
			"Status_Icon_Completed": "img/png/32x32/accept.png",
			"GoalsListHeader": "Public goals",
			"WisherListHeader":"Goal wishers",
			"ParticipantListHeader":"participants",
			"Act_AddAsCollaborator": "participate",
			"Participant_AddedMessage": "Participant added",
			"Act_CreateIssue":"Create new issue",
			"LinkToGoal":"Link to goal",
			"CreateGoal":"Create goal",
			"Status_Unknown": "Unknown",
			"IssueListHeader":"Issues",
			"IssueEditHeader":"Issue",
			"Act_AddIssue":"Add Issue",
			//"Act_CreateIssue":"",
			"Act_AddAsGoal":"Add goal",
			"AddReference":"Add",
			"AddReference":"Remove",
			"Act_NextPage":"Next",
			"Act_PrevPage":"Prev",
			"IssueSollution":"Solution",
			"Wisher": "Wisher",
			
			"AskLoginMessage":"Please login with facebook!",
			"GoalDetailHeader":"Details",
			"IssueDetailHeader":"Details",
			"Participants":"Participants",
			"RegionalLocation":"Location",
			"Act_Create":"Create",
			"Anonymous": "Anonymous",
			"Delete":"Delete",
			"DeleteConfirm":"Delete",
			"Act_Complete": "Ok",
			"Related": "Related",
			
			
			"LogIn": "Please log in",
			"NoPermissionToDelete": "No permission to delete",
			"NoPermissionToEdit": "No permission to edit",
			"Nav_Help":"Help",
			"HelpTitle": "Faq",
			"HelpLinkMessage": "Help",
			"HelpHeader": "If you are having any questions about the GoalShare, please contact us by  goalshare@open-opinion.org.",
			"FAQHeader":"Here are answers to some common questions",
			"FAQ_EnableCookiesTitle": "There is a problem with the Facebook login.",
			"FAQ_EnableCookiesText": "Please make sure that cookies, including third-party cookies, are enabled in the browser.",
			"DirectLink":"Link to the goal",
			"Act_OK": "Ok",
			
			"Act_FocusOnGoal": "Focus on goal",
			"GoalTree_Instructions" : "Mouse wheel or double click zooms the tree view",
			"Tags": "Tags",
			"AddTag":"Add",
			"CC":"<a rel=\"license\" href=\"http://creativecommons.org/licenses/by/4.0/\"><img alt=\"Creative Commons License\" style=\"border-width:0\" src=\"https://i.creativecommons.org/l/by/4.0/88x31.png\" /></a><br />The data inputted to GoalShare system is licensed under <a rel=\"license\" href=\"http://creativecommons.org/licenses/by/4.0/\">Creative Commons Attribution 4.0 International License</a>.",
			"CCSmall":"<a rel=\"license\" href=\"http://creativecommons.org/licenses/by/4.0/\">The data inputted to GoalShare system is licensed under <a rel=\"license\" href=\"http://creativecommons.org/licenses/by/4.0/\">Creative Commons Attribution 4.0 International License</a>.",
			"SOMEURI":"User's url",
			"addUserByURI":"Add user",
			"addUser":"Add user",
			"Add":"Add",
			"Last": "Last"
		},
		currentLanguage: "en",
	setLanguage: function(lang){
		
		if( lang != Locale.currentLanguage ){
			Locale.currentLanguage = lang;
			var nLang = lang;
			$.ajax({
				url: "locale-" + lang,
				async: false,
			}).done(function(data){ 
				Locale.dict = data;  
				});
		}else{
			//console.log("Lang diff:" + Locale.currentLanguage + " " + lang);
		}
	},
		
};

function translateStatus(statusCode){
	var status = "-"; 

	try{
	var status = Locale.dict.Status_Unknown;
		switch(statusCode){
			case "NotStarted":
				status = Locale.dict.Status_NotStarted;
				break;
			case "InProgress":
				status = Locale.dict.Status_InProgress;
				break;
			case "Completed":
				status = Locale.dict.Status_Completed;
				break;
			case "Aborted":
				status = Locale.dict.Status_Aborted;
				break;
		}
	}catch(err ){}
		return status;		
}
function translateStatusImage(statusCode){
	var status = ""; 
	
	
	try{
		var status = Locale.dict.Status_Unknown;
		switch(statusCode){
			case "NotStarted":
				status = Locale.dict.Status_Icon_NotStarted;
				break;
			case "InProgress":
				status = Locale.dict.Status_Icon_InProgress;
				break;
			case "Completed":
				status = Locale.dict.Status_Icon_Completed;
				break;
			case "Aborted":
				status = Locale.dict.Status_Icon_Aborted;
				break;
		}
	}catch(err ){}
	return status;		
}

/*
 * Date UI format 
 */
function formatDate(date){
	try{
		var desDate = new Date(Date.parse(date));	
		if( !isNaN( desDate.getTime() ) )
			return desDate.format(Locale.dict.X_DateFormat);
	}catch(err){
	}
		return " ... ";
}


function getTimezoneOffset(){
	var offset = new Date().getTimezoneOffset();
	offset = ((offset<0? '+':'-')+ // Note the reversed sign!
	          pad(parseInt(Math.abs(offset/60)), 2)+
	          pad(Math.abs(offset%60), 2));
	return offset;
}


$.urlParam = function(name){
    var results = new RegExp('[\\?&]' + name + '=([^&#]*)').exec(window.location.href);
    if (results==null){
       return null;
    }
    else{
       return results[1] || 0;
    }
}

function shortenText(text, maxLength) {
    if (!text)
    	return "";
	var ret = text;
    if (ret.length > maxLength) {
        ret = ret.substr(0,maxLength-3) + "...";
    }
    return ret;
}

/**
 * Converts wikipedia URLs to dbpedia URIs
 * @param link
 * @returns
 */
function pediaLinkConvert(link){
	var wikipediaURIPart = "http://en.wikipedia.org/wiki/";
	var dbpediaURIPart = "http://dbpedia.org/resource/";
	var wpr = new RegExp("^/http:\/\/en.wikipedia.org\/wiki\/");
	if( wpr.test(link) ){
		//wikipedia link
		return(link.replace(/http:\/\/en.wikipedia.org\/wiki\//, "http://dbpedia.org/resource/"));
	}else{
		return(link.replace(/"http:\/\/dbpedia.org\/resource\//, "http://en.wikipedia.org/wiki/"));
	}
}
function removeURLParameter(url, parameter) {
    //prefer to use l.search if you have a location/link object
    var urlparts= url.split('?');   
    if (urlparts.length>=2) {

        var prefix= encodeURIComponent(parameter)+'=';
        var pars= urlparts[1].split(/[&;]/g);

        //reverse iteration as may be destructive
        for (var i= pars.length; i-- > 0;) {    
            //idiom for string.startsWith
            if (pars[i].lastIndexOf(prefix, 0) !== -1) {  
                pars.splice(i, 1);
            }
        }

        url= urlparts[0]+'?'+pars.join('&');
        return url;
    } else {
        return url;
    }
}
