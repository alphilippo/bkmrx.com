// 
//	jQuery Validate example script
//
//	Prepared by David Cochran
//	Modified by rob hammond
//	Free for your use -- No warranties, no guarantees!
//

$(document).ready(function(){
	$('#register-form').validate({
		rules: {
			username: {
				// minlength: 3,
				required: true
			},
			email: {
				required: true,
				email: true
			},
			pass: {
				minlength: 5,
				required: true
			},
			pass2: {
				minlength: 5,
				required: true
			}
		},
		highlight: function(label) {
			$(label).closest('.form-group').addClass('has-error');
		},
		success: function(label) {
			label
			.closest('.form-group').addClass('has-success');
		}
	});

	$("input#new-user").click(function () {
		$('#register-form').show();
		$('#login-form').hide();
		$('#div-confirm').show();
		$('#div-username').show();
		$('#div-email').show();
		$('#div-password').show();
		$('#register').show();
	});

	$("input#existing").click(function () {
		$('#register-form').hide();
		$('#login-form').show();
	});

}); // end document.ready

